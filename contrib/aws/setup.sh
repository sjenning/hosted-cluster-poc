#!/bin/bash

set -eu

function get_infra_name()
{
  local __infra_name_var="${1}"

  local infra_name=""
  infra_name="$(oc get infrastructure/cluster -o jsonpath='{ .status.infrastructureName }')"

  eval $__infra_name_var="'${infra_name}'"
}

function get_lb_info()
{
  local infraname="${1}"
  local __az_var="${2}"
  local __vpc_var="${3}"
  local __subnet_var="${4}"

  local lb_file="$(mktemp)"
  local vpc=""
  local azs=""
  local az=""
  local subnet=""

  aws elbv2 describe-load-balancers --name "${infraname}-ext" > "${lb_file}"
  vpc="$(cat "${lb_file}" | jq -r '.LoadBalancers[0].VpcId')"
  azs="$(cat "${lb_file}" | jq -r '.LoadBalancers[0].AvailabilityZones[].ZoneName')"
  for i in ${azs}; do
    if oc get machines -n openshift-machine-api | grep "${infraname}-worker-${i}" &> /dev/null; then
      az="${i}"
      break
    fi
  done
  if [[ -z "${az}" ]]; then
    "Could not find a suitable availability zone"
    exit 1
  fi
  subnet="$(cat "${lb_file}" | jq -r ".LoadBalancers[0].AvailabilityZones[] | select(.ZoneName==\"${az}\") | .SubnetId")"
  echo "Host cluster VPC is ${vpc}"
  echo "Using availability zone ${az} with subnet ${subnet}"

  eval $__az_var="'${az}'"
  eval $__vpc_var="'${vpc}'"
  eval $__subnet_var="'${subnet}'"
}

function get_host_machine_info()
{
  local infraname="${1}"
  local az="${2}"
  local __machine_ip_var="${3}"
  local __instance_id_var="${4}"

  local machine=""
  local machine_ip=""
  local instance_id=""
  local machine_file="$(mktemp)"

  machine="$(oc get machines -n openshift-machine-api | grep "${infraname}-worker-${az}" | awk '{ print $1 }' | head -n1)"
  oc get machines ${machine} -n openshift-machine-api -o json  > "${machine_file}"
  machine_ip="$(cat "${machine_file}" | jq -r '.status.addresses[] | select(.type == "InternalIP") | .address')"
  instance_id="$(cat "${machine_file}" | jq -r '.status.providerStatus.instanceId')"

  echo "Found management cluster machine with IP ${machine_ip} in ${az}."

  eval $__machine_ip_var="'${machine_ip}'"
  eval $__instance_id_var="'${instance_id}'"
}

function get_zone_id()
{
  local domain_name="${1}"
  local __zone_id_var="${2}"

  local zone_id=""

  zone_id="$(aws route53 list-hosted-zones-by-name --dns-name "${domain_name}" | jq -r '.HostedZones[0].Id')"
  echo "DNS: Found hosted zone ${zone_id} for ${domain_name}"

  eval $__zone_id_var="'${zone_id}'"
}

function ensure_eip()
{
  local infraname="${1}"
  local eip_name="${2}"
  local __allocation_id_var="${3}"
  local __ip_var="${4}"

  local address_file="$(mktemp)"
  local allocation_id=""
  local ip_address=""

  aws ec2 describe-addresses --filter "Name=tag:Name,Values=${eip_name}" > "${address_file}"
  local allocation_id="$(cat "${address_file}" | jq -r '.Addresses[0].AllocationId')"
  if [[ -z "${allocation_id}" || "${allocation_id}" == "null" ]]; then
    echo "IP address ${eip_name} not found, creating one"
    aws ec2 allocate-address --domain vpc > "${address_file}"
    allocation_id="$(cat "${address_file}" | jq -r '.AllocationId')"
    ip_address="$(cat "${address_file}" | jq -r '.PublicIp')"
    echo "Address allocated with allocation ID ${allocation_id}"
    aws ec2 create-tags --resources "${allocation_id}" \
      --tags "Key=kubernetes.io/cluster/${infraname},Value=owned" "Key=Name,Value=${eip_name}"
  else
    echo "Existing public IP ${eip_name} found with allocation ID ${allocation_id}"
    ip_address="$(cat "${address_file}" | jq -r '.Addresses[0].PublicIp')"
  fi
  echo "${eip_name} public IP is ${ip_address}"

  eval $__allocation_id_var="'${allocation_id}'"
  eval $__ip_var="'${ip_address}'"
}


function ensure_nlb()
{
  local infraname="${1}"
  local nlb_name="${2}"
  local subnet="${3}"
  local __arn_var="${4}"
  local __dns_name_var="${5}"
  local allocation_id="${6:-}"

  local nlb_file="$(mktemp)"
  local arn=""
  local dns_name=""

  if ! aws elbv2 describe-load-balancers --names "${nlb_name}" > "${nlb_file}" 2> /dev/null; then
    arn=""
  else
    arn="$(cat ${nlb_file} | jq -r '.LoadBalancers[0].LoadBalancerArn')"
  fi

  if [[ -z "${arn}" ]]; then
    echo "API load balancer not found, creating one"
    if [[ -z "${allocation_id}" ]]; then
      aws elbv2 create-load-balancer --name "${nlb_name}" \
        --subnets "${subnet}" \
        --scheme internet-facing \
        --type network \
        --tags "Key=kubernetes.io/cluster/${infraname},Value=owned" > "${nlb_file}"
    else
      aws elbv2 create-load-balancer --name "${nlb_name}" \
        --subnet-mappings "SubnetId=${subnet},AllocationId=${allocation_id}" \
        --scheme internet-facing \
        --type network \
        --tags "Key=kubernetes.io/cluster/${infraname},Value=owned" > "${nlb_file}"
    fi
    arn="$(cat "${nlb_file}" | jq -r '.LoadBalancers[0].LoadBalancerArn')"
  else
    echo "Existing load balancer found with ARN ${arn}"
  fi
  dns_name="$(cat "${nlb_file}" | jq -r '.LoadBalancers[0].DNSName')"
  echo "Load balancer ${nlb_name} DNS name is ${dns_name}"
  eval $__arn_var="'$arn'"
  eval $__dns_name_var="'$dns_name'"
}


function ensure_target_group()
{
  local infraname="${1}"
  local vpc="${2}"
  local tg_name="${3}"
  local port="${4}"
  local __arn_var="${5}"

  local tg_file="$(mktemp)"
  local tg_arn=""

  if ! aws elbv2 describe-target-groups --names "${tg_name}" > "${tg_file}" 2> /dev/null; then
    tg_arn=""
  else
    tg_arn="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
    if [[ "${tg_arn}" == "null" ]]; then
      tg_arn=""
    fi
    tg_port="$(cat "${tg_file}" | jq -r '.TargetGroups[0].Port')"
    if [[ "${tg_port}" == "null" ]]; then
      tg_port=""
    fi
    if [[ "${tg_port}" != "${port}" ]]; then
      echo "Found target group ${tg_name}, but it does not point to the right port. Deleting."
      aws elbv2 delete-target-group --target-group-arn "${tg_arn}"
      tg_arn=""
    fi
  fi
  if [[ -z "${tg_arn}" ]]; then
    echo "Creating target group ${tg_name}"
    aws elbv2 create-target-group --name "${tg_name}" \
      --protocol TCP \
      --port ${port} \
      --vpc-id ${vpc} \
      --health-check-protocol TCP \
      --health-check-enabled \
      --health-check-interval-seconds 10 \
      --health-check-timeout-seconds 10 \
      --healthy-threshold-count 2 \
      --unhealthy-threshold-count 2 \
      --target-type ip > "${tg_file}"
    tg_arn="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
    echo "Target group ${tg_name} created with ARN ${tg_arn}"
    aws elbv2 add-tags --resource-arns "${tg_arn}" \
      --tags "Key=kubernetes.io/cluster/${infraname},Value=owned"
  else
    echo "Target group ${tg_name} already exists."
  fi

  eval $__arn_var="'$tg_arn'"
}

function ensure_udp_target_group()
{
  local infraname="${1}"
  local vpc="${2}"
  local tg_name="${3}"
  local port="${4}"
  local hcport="${5}"
  local __arn_var="${6}"

  local tg_file="$(mktemp)"
  local tg_arn=""

  if ! aws elbv2 describe-target-groups --names "${tg_name}" > "${tg_file}" 2> /dev/null; then
    tg_arn=""
  else
    tg_arn="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
    if [[ "${tg_arn}" == "null" ]]; then
      tg_arn=""
    fi
    tg_port="$(cat "${tg_file}" | jq -r '.TargetGroups[0].Port')"
    if [[ "${tg_port}" == "null" ]]; then
      tg_port=""
    fi
    if [[ "${tg_port}" != "${port}" ]]; then
      echo "Found target group ${tg_name}, but it does not point to the right port. Deleting."
      aws elbv2 delete-target-group --target-group-arn "${tg_arn}"
      tg_arn=""
    fi
  fi
  if [[ -z "${tg_arn}" ]]; then
    echo "Creating target group ${tg_name}"
    aws elbv2 create-target-group --name "${tg_name}" \
      --protocol UDP \
      --port ${port} \
      --vpc-id ${vpc} \
      --health-check-protocol TCP \
      --health-check-port "${hcport}" \
      --health-check-enabled \
      --health-check-interval-seconds 10 \
      --health-check-timeout-seconds 10 \
      --healthy-threshold-count 2 \
      --unhealthy-threshold-count 2 \
      --target-type instance > "${tg_file}"
    tg_arn="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
    echo "Target group ${tg_name} created with ARN ${tg_arn}"
    aws elbv2 add-tags --resource-arns "${tg_arn}" \
      --tags "Key=kubernetes.io/cluster/${infraname},Value=owned"
  else
    echo "Target group ${tg_name} already exists."
  fi

  eval $__arn_var="'$tg_arn'"
}

function ensure_target()
{
  local tg_arn="${1}"
  local ip="${2}"
  local target_file="$(mktemp)"
  local target_id=""

  aws elbv2 describe-target-health --target-group-arn "${tg_arn}" > "${target_file}"
  target_id="$(cat "${target_file}" | jq -r '.TargetHealthDescriptions[0].Target.Id')"
  if [[ "${target_id}" == "null" ]]; then
    target_id=""
  fi
  if [[ -n "${target_id}" && "${target_id}" != "${ip}" ]]; then
    echo "Found target but it does not point to the correct IP. Removing target"
    aws elbv2 deregister-targets --target-group-arn "${tg_arn}" --targets "Id=${target_id}"
    target_id=""
  fi

  if [[ -z "${target_id}" ]]; then
    echo "Registering API load balancer target with IP ${ip}"
    aws elbv2 register-targets --target-group-arn "${tg_arn}" --targets "Id=${ip}"
  fi
}

function ensure_listener()
{
  local nlb_arn="${1}"
  local tg_arn="${2}"
  local port="${3}"
  local protocol="${4:-TCP}"
  local listener_file="$(mktemp)"
  local listener_arn=""
  local listener_target=""

  aws elbv2 describe-listeners --load-balancer-arn "${nlb_arn}" > "${listener_file}"
  listener_arn="$(cat "${listener_file}" | jq -r ".Listeners[] | select(.Port==${port}) | .ListenerArn")"
  if [[ "${listener_arn}" == "null" ]]; then
    listener_arn=""
  fi
  if [[ -n "${listener_arn}" ]]; then
    listener_target="$(cat "${listener_file}" | jq -r ".Listeners[] | select(.Port==${port}) | .DefaultActions[0].TargetGroupArn")"
    if [[ "${listener_target}" != "${tg_arn}" ]]; then
      echo "Found listener, but it does not have the correct target. Removing"
      aws elbv2 delete-listener --listener-arn "${listener_arn}"
      listener_arn=""
    fi
  fi
  if [[ -z "${listener_arn}" ]]; then
    echo "Creating listener for load balancer ${nlb_arn}"
    aws elbv2 create-listener --load-balancer-arn "${nlb_arn}" --protocol ${protocol} --port ${port} \
      --default-actions "Type=forward,TargetGroupArn=${tg_arn}" > "${listener_file}"
    listener_arn="$(cat "${listener_file}" | jq ".Listeners[] | select(.Port==${port}) | .ListenerArn")"
    echo "Listener created with ARN ${listener_arn}"
  fi
}


function ensure_cname_record()
{
  local zone_id="${1}"
  local dns_name="${2}"
  local target_name="${3}"

  local change_batch_file="$(mktemp)"
  cat <<EOF > "${change_batch_file}"
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${dns_name}",
        "Type": "CNAME",
        "TTL": 30,
        "ResourceRecords": [
          {
            "Value": "${target_name}"
          }
        ]
      }
    }
  ]
}
EOF
  local change_batch="$(cat "${change_batch_file}" | jq -c)"
  echo "DNS: Upserting recordset for ${dns_name}"
  aws route53 change-resource-record-sets --hosted-zone-id="${zone_id}" --change-batch "${change_batch}" > /dev/null
}

function ensure_workers_allow_nodeport_access()
{
  local infraname="${1}"
  local sg_file="$(mktemp)"
  local sg_id=""
  local nodeport_rule=""
  aws ec2 describe-security-groups --filters Name=tag:Name,Values=${infraname}-worker-sg > "${sg_file}"
  sg_id="$(cat "${sg_file}" | jq -r '.SecurityGroups[0].GroupId')"
  nodeport_rule="$(cat "${sg_file}" | jq '.SecurityGroups[0].IpPermissions[] | select(.FromPort==30000) | select(.IpProtocol=="tcp") | .IpRanges[] | select(.CidrIp == "10.0.0.0/16")')"
  if [[ -z "${nodeport_rule}" || "${nodeport_rule}" == "null" ]]; then
    echo "Adding worker security group rule to allow internal access to tcp nodeports"
    aws ec2 authorize-security-group-ingress --group-id "${sg_id}" --ip-permissions 'FromPort=30000,ToPort=32767,IpProtocol=tcp,IpRanges=[{CidrIp=10.0.0.0/16}]'
  fi

  nodeport_rule="$(cat "${sg_file}" | jq '.SecurityGroups[0].IpPermissions[] | select(.FromPort==30000) | select(.IpProtocol=="udp") | .IpRanges[] | select(.CidrIp == "0.0.0.0/0")')"
  if [[ -z "${nodeport_rule}" || "${nodeport_rule}" == "null" ]]; then
    echo "Adding worker security group rule to allow internal access to udp nodeports"
    aws ec2 authorize-security-group-ingress --group-id "${sg_id}" --ip-permissions 'FromPort=30000,ToPort=32767,IpProtocol=udp,IpRanges=[{CidrIp=0.0.0.0/0}]'
  fi
}

function ensure_ignition_bucket()
{
  local infraname="${1}"
  local bucket_name="${2}"
  local ignition_file="${3}"

  # Ensure that there is an S3 bucket that will hold the worker ignition data
  local existing_bucket="$(aws s3api list-buckets | jq ".Buckets[] | select(.Name==\"${bucket_name}\")")"
  if [[ -z "${existing_bucket}" || "${existing_bucket}" == "null" ]]; then
    echo "Ignition bucket does not exist. Creating one."
    aws s3api create-bucket --bucket "${bucket_name}" --acl public-read
    aws s3api put-bucket-tagging --bucket "${bucket_name}" --tagging "TagSet=[{Key=kubernetes.io/cluster/${infraname},Value=owned}]"
  fi
  echo "Copying bootstrap ignition to bucket ${bucket_name}"
  aws s3 cp "${ignition_file}" "s3://${bucket_name}/final.ign" --acl public-read
}

# Create a machineset for the user cluster
function generate_worker_machineset()
{
  local infraname="${1}"
  local az="${2}"
  local clustername="${3}"
  local lbname="${4}"
  local outputfile="${5}"

  local machineset_json="$(mktemp)"
  local machineset_name="$(oc get machineset -n openshift-machine-api | grep "${infraname}-worker-${az}" | awk '{ print $1 }')"
  oc get machineset "${machineset_name}" -n openshift-machine-api -o json > "${machineset_json}"
  local worker_ms_name="${INFRANAME}-${NAMESPACE}-worker"
  local machineset_xform="\
  del(.status)|\
  del(.metadata.creationTimestamp)|\
  del(.metadata.generation)|\
  del(.metadata.resourceVersion)|\
  del(.metadata.selfLink)|\
  del(.metadata.uid)|\
  del(.spec.template.spec.metadata)|\
  del(.spec.template.spec.providerSpec.value.publicIp)|\
  .spec.replicas=2|\
  .metadata.name=\"${worker_ms_name}\"|\
  .spec.selector.matchLabels[\"machine.openshift.io/cluster-api-machineset\"]=\"${worker_ms_name}\"|\
  .spec.template.metadata.labels[\"machine.openshift.io/cluster-api-machineset\"]=\"${worker_ms_name}\"|\
  .spec.template.spec.providerSpec.value.userDataSecret.name=\"${clustername}-worker-user-data\"|\
  .spec.template.spec.providerSpec.value += {loadBalancers:[{name:\"${lbname}\",type:\"network\"}]}"

  cat "${machineset_json}" | jq "${machineset_xform}" > "${outputfile}"
}

REPODIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/../.."
source "${REPODIR}/config.sh"

# Ensure make-pki is run first so we can create an ignition file
# When this script is called from install-openshift.sh, this is already done
${REPODIR}/make-pki.sh

pushd ${REPODIR}/ignition-generator
./make-ignition.sh
popd

# Gather information about current management cluster
get_infra_name INFRANAME
get_lb_info "${INFRANAME}" AZ VPC SUBNET
get_host_machine_info "${INFRANAME}" "${AZ}" HOST_MACHINE_IP HOST_MACHINE_ID
get_zone_id "${PARENT_DOMAIN}" ZONE_ID

# Create API load balancer
APILB="${INFRANAME}-${NAMESPACE}-api"
ensure_eip "${INFRANAME}" "${APILB}" API_ALLOCATION_ID API_PUBLIC_IP
ensure_nlb "${INFRANAME}" "${APILB}" "${SUBNET}" API_NLB_ARN API_NLB_DNS_NAME "${API_ALLOCATION_ID}" 
ensure_target_group "${INFRANAME}" "${VPC}" "${APILB}" "${API_NODEPORT}" API_TG_ARN
ensure_target "${API_TG_ARN}" "${HOST_MACHINE_IP}"
ensure_listener "${API_NLB_ARN}" "${API_TG_ARN}" "6443"
ensure_cname_record "${ZONE_ID}" "${EXTERNAL_API_DNS_NAME}" "${API_NLB_DNS_NAME}"

# Create router load balancer
ROUTERLB="${INFRANAME}-${NAMESPACE}-apps"
ensure_nlb "${INFRANAME}" "${ROUTERLB}" "${SUBNET}" ROUTER_NLB_ARN ROUTER_NLB_DNS_NAME
ensure_target_group "${INFRANAME}" "${VPC}" "${INFRANAME}-${NAMESPACE}-h" "${ROUTER_NODEPORT_HTTP}" ROUTER_HTTP_TG_ARN
ensure_listener "${ROUTER_NLB_ARN}" "${ROUTER_HTTP_TG_ARN}" "80"
ensure_target_group "${INFRANAME}" "${VPC}" "${INFRANAME}-${NAMESPACE}-s" "${ROUTER_NODEPORT_HTTPS}" ROUTER_HTTPS_TG_ARN
ensure_listener "${ROUTER_NLB_ARN}" "${ROUTER_HTTPS_TG_ARN}" "443"
ensure_cname_record "${ZONE_ID}" "*.${INGRESS_SUBDOMAIN}" "${ROUTER_NLB_DNS_NAME}"

# Create vpn load balancer
VPNLB="${INFRANAME}-${NAMESPACE}-vpn"
ensure_nlb "${INFRANAME}" "${VPNLB}" "${SUBNET}" VPN_NLB_ARN VPN_NLB_DNS_NAME
ensure_udp_target_group "${INFRANAME}" "${VPC}" "${VPNLB}" "${OPENVPN_NODEPORT}" "${API_NODEPORT}" VPN_TG_ARN
ensure_target "${VPN_TG_ARN}" "${HOST_MACHINE_ID}"
ensure_listener "${VPN_NLB_ARN}" "${VPN_TG_ARN}" "${EXTERNAL_OPENVPN_PORT}" UDP
ensure_cname_record "${ZONE_ID}" "${EXTERNAL_OPENVPN_DNS_NAME}" "${VPN_NLB_DNS_NAME}"


# Call render again on the kube-apiserver so we get the latest
# external IP
cat <<EOF > "${REPODIR}/config_api_ip.sh"
export EXTERNAL_API_IP_ADDRESS="${API_PUBLIC_IP}"
EOF

pushd "${REPODIR}/kube-apiserver"
./render.sh
popd

# Ensure that the workers security group allows access to node ports
ensure_workers_allow_nodeport_access "${INFRANAME}"

# Ensure that a bucket exists with the ignition file for workers in this cluster
IGNITION_BUCKET="${INFRANAME}-${NAMESPACE}-ign"
ensure_ignition_bucket "${INFRANAME}" "${IGNITION_BUCKET}" "${REPODIR}/ignition-generator/final.ign"

# Create a bootstrap ignition that points to the final.ign in the S3 bucket
cat <<EOF > "${REPODIR}/machine-api/machine-user-data.ign"
{"ignition":{"config":{"append":[{"source":"https://${IGNITION_BUCKET}.s3.amazonaws.com/final.ign","verification":{}}]},"security":{},"timeouts":{},"version":"2.2.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}
EOF

# Generate machineset for cluster workers
generate_worker_machineset "${INFRANAME}" "${AZ}" "${NAMESPACE}" "${ROUTERLB}" "${REPODIR}/machine-api/machineset.json"
pushd "${REPODIR}/machine-api"
./render.sh
popd
