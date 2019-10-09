#!/bin/bash

set -e

REPODIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/../.."

source "${REPODIR}/config.sh"

#Ensure make-pki is run first so we can create an ignition file
# when this script is called from install-openshift.sh, this is already done
${REPODIR}/make-pki.sh

pushd ${REPODIR}/ignition-generator
./make-ignition.sh
popd

export INFRANAME="$(oc get infrastructure/cluster -o jsonpath='{ .status.infrastructureName }')"
lb_file="$(mktemp)"
aws elbv2 describe-load-balancers --name "${INFRANAME}-ext" > "${lb_file}"
export VPC="$(cat "${lb_file}" | jq -r '.LoadBalancers[0].VpcId')"
export AZS="$(cat "${lb_file}" | jq -r '.LoadBalancers[0].AvailabilityZones[].ZoneName')"
for az in ${AZS}; do
  if oc get machines -n openshift-machine-api | grep "${INFRANAME}-worker-${az}" &> /dev/null; then
    export AZ="${az}"
    break
  fi
done
if [[ -z "${AZ}" ]]; then
  "Could not find a suitable availability zone"
fi
export SUBNET="$(cat "${lb_file}" | jq -r ".LoadBalancers[0].AvailabilityZones[] | select(.ZoneName==\"${AZ}\") | .SubnetId")"


echo "Host cluster VPC is ${VPC}"
echo "Using availability zone ${AZ} with subnet ${SUBNET}"

# Create a Network Load Balancer for the API server
# as the internal apiserver service IP endpoint
address_file="$(mktemp)"
aws ec2 describe-addresses --filter Name=tag:Name,Values=${INFRANAME}-${NAMESPACE}-api > "${address_file}"
export ALLOCATION_ID="$(cat ${address_file} | jq -r '.Addresses[0].AllocationId')"
if [[ -z "${ALLOCATION_ID}" || "${ALLOCATION_ID}" == "null" ]]; then
  echo "Public IP address not found, creating one"
  aws ec2 allocate-address --domain vpc > "${address_file}"
  export ALLOCATION_ID="$(cat "${address_file}" | jq -r '.AllocationId')"
  export API_PUBLIC_IP="$(cat "${address_file}" | jq -r '.PublicIp')"
  echo "Address allocated with allocation ID ${ALLOCATION_ID}"
  aws ec2 create-tags --resources "${ALLOCATION_ID}" \
    --tags "Key=kubernetes.io/cluster/${INFRANAME},Value=owned" "Key=Name,Value=${INFRANAME}-${NAMESPACE}-api"
else
  echo "Existing public IP found with allocation ID ${ALLOCATION_ID}"
  export API_PUBLIC_IP="$(cat "${address_file}" | jq -r '.Addresses[0].PublicIp')"
fi
echo "API public IP is ${API_PUBLIC_IP}"

nlb_file="$(mktemp)"
export APILBNAME="${INFRANAME}-${NAMESPACE}-api"
if ! aws elbv2 describe-load-balancers --names "${APILBNAME}" > "${nlb_file}" 2> /dev/null; then
  export NLB_ARN=""
else
  export NLB_ARN="$(cat ${nlb_file} | jq -r '.LoadBalancers[0].LoadBalancerArn')"
fi
if [[ -z "${NLB_ARN}" ]]; then
  echo "API load balancer not found, creating one"
  aws elbv2 create-load-balancer --name "${APILBNAME}" \
    --subnet-mappings "SubnetId=${SUBNET},AllocationId=${ALLOCATION_ID}" \
    --scheme internet-facing \
    --type network \
    --tags "Key=kubernetes.io/cluster/${INFRANAME},Value=owned" > "${nlb_file}"
  export NLB_ARN="$(cat "${nlb_file}" | jq -r '.LoadBalancers[0].LoadBalancerArn')"
else
  echo "Existing load balancer found with ARN ${NLB_ARN}"
fi
export NLB_DNS_NAME="$(cat "${nlb_file}" | jq -r '.LoadBalancers[0].DNSName')"
echo "API load balancer DNS name is ${NLB_DNS_NAME}"

tg_file="$(mktemp)"
if ! aws elbv2 describe-target-groups --names "${APILBNAME}" > "${tg_file}" 2> /dev/null; then
  export TG_ARN=""
else
  export TG_ARN="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
  if [[ "${TG_ARN}" == "null" ]]; then
    export TG_ARN=""
  fi
  TG_PORT="$(cat "${tg_file}" | jq -r '.TargetGroups[0].Port')"
  if [[ "${TG_PORT}" == "null" ]]; then
    export TG_PORT=""
  fi
  if [[ "${TG_PORT}" != "${API_NODEPORT}" ]]; then
    echo "Found API load balancer target group, but it does not point to the right port. Deleting."
    aws elbv2 delete-target-group --target-group-arn "${TG_ARN}"
    export TG_ARN=""
  fi
fi
if [[ -z "${TG_ARN}" ]]; then
  echo "Creating target group for API load balancer"
  aws elbv2 create-target-group --name "${INFRANAME}-${NAMESPACE}-api" \
    --protocol TCP \
    --port ${API_NODEPORT} \
    --vpc-id ${VPC} \
    --health-check-protocol TCP \
    --health-check-enabled \
    --health-check-interval-seconds 10 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --target-type ip > "${tg_file}"
  export TG_ARN="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
  echo "Target group for API created with ARN ${TG_ARN}"
  aws elbv2 add-tags --resource-arns "${TG_ARN}" \
    --tags "Key=kubernetes.io/cluster/${INFRANAME},Value=owned"
else
  echo "Target group for API load balancer already exists."
fi

export MACHINE="$(oc get machines -n openshift-machine-api | grep "${INFRANAME}-worker-${AZ}" | awk '{ print $1 }' | head -n1)"
export MACHINE_IP="$(oc get machines $MACHINE -n openshift-machine-api -o json | jq -r '.status.addresses[] | select(.type == "InternalIP") | .address')"
echo "Found management cluster machine with IP ${MACHINE_IP} in ${AZ}. Using that as the load balancer target"

tgt_file="$(mktemp)"
aws elbv2 describe-target-health --target-group-arn "${TG_ARN}" > "${tgt_file}"
export TARGET_ID="$(cat "${tgt_file}" | jq -r '.TargetHealthDescriptions[0].Target.Id')"
if [[ "${TARGET_ID}" == "null" ]]; then
  export TARGET_ID=""
fi
if [[ -n "${TARGET_ID}" && "${TARGET_ID}" != "${MACHINE_IP}" ]]; then
  echo "Found API load balancer target but it does not point to the correct IP. Removing target"
  aws elbv2 deregister-targets --target-group-arn "${TG_ARN}" --targets "Id=${TARGET_ID}"
  export TARGET_ID=""
fi

if [[ -z "${TARGET_ID}" ]]; then
  echo "Registering API load balancer target with IP ${MACHINE_IP}"
  aws elbv2 register-targets --target-group-arn "${TG_ARN}" --targets "Id=${MACHINE_IP}"
fi

listener_file="$(mktemp)"
aws elbv2 describe-listeners --load-balancer-arn "${NLB_ARN}" > "${listener_file}"
export LISTENER_ARN="$(cat "${listener_file}" | jq -r '.Listeners[0].ListenerArn')"
if [[ "${LISTENER_ARN}" == "null" ]]; then
  export LISTENER_ARN=""
fi
if [[ -n "${LISTENER_ARN}" ]]; then
  export LISTENER_TARGET="$(cat "${listener_file}" | jq -r '.Listeners[0].DefaultActions[0].TargetGroupArn')"
  if [[ "${LISTENER_TARGET}" != "${TG_ARN}" ]]; then
    echo "Found API load balancer listener, but it does not have the correct target. Removing"
    aws elbv2 delete-listener --listener-arn "${LISTENER_ARN}"
    export LISTENER_ARN=""
  fi
else
  echo "Listener for API load balancer already exists"
fi

if [[ -z "${LISTENER_ARN}" ]]; then
  echo "Creating listener for API load balancer"
  aws elbv2 create-listener --load-balancer-arn "${NLB_ARN}" --protocol TCP --port 6443 \
    --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" > "${listener_file}"
  export LISTENER_ARN="$(cat "${listener_file}" | jq '.Listeners[0].ListenerArn')"
  echo "Listener created with ARN ${LISTENER_ARN}"
fi

# Point public and private DNS zones to new network load balancer
PUBLIC_ZONE_ID="$(aws route53 list-hosted-zones-by-name --dns-name "${PARENT_DOMAIN}" | jq -r '.HostedZones[0].Id')"
echo "DNS: Found hosted zone ${PUBLIC_ZONE_ID} for ${PARENT_DOMAIN}"

change_batch_file="$(mktemp)"
cat <<EOF > "${change_batch_file}"
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${EXTERNAL_API_DNS_NAME}",
        "Type": "CNAME",
        "TTL": 30,
        "ResourceRecords": [
          {
            "Value": "${NLB_DNS_NAME}"
          }
        ]
      }
    }
  ]
}
EOF
CHANGE_BATCH="$(cat "${change_batch_file}" | jq -c)"

echo "DNS: Upserting recordset for ${EXTERNAL_API_DNS_NAME}"
aws route53 change-resource-record-sets --hosted-zone-id="${PUBLIC_ZONE_ID}" --change-batch "${CHANGE_BATCH}" > /dev/null


# Create a network Load Balancer for the Router
# and register a wildcard DNS entry for it
router_nlb_file="$(mktemp)"
export ROUTERLBNAME="${INFRANAME}-${NAMESPACE}-apps"
if ! aws elbv2 describe-load-balancers --name "${ROUTERLBNAME}" > "${router_nlb_file}" 2> /dev/null; then
  export ROUTER_NLB_ARN=""
else
  export ROUTER_NLB_ARN="$(cat ${router_nlb_file} | jq -r '.LoadBalancers[0].LoadBalancerArn')"
  if [[ "${ROUTER_NLB_ARN}" == "null" ]]; then
    export ROUTER_NLB_ARN=""
  fi
fi
if [[ -z "${ROUTER_NLB_ARN}" ]]; then
  echo "Router load balancer not found. Creating it"
  aws elbv2 create-load-balancer --name "${ROUTERLBNAME}" \
    --subnets "${SUBNET}" \
    --scheme internet-facing \
    --type network \
    --tags "Key=kubernetes.io/cluster/${INFRANAME},Value=owned" > "${router_nlb_file}"
  export ROUTER_NLB_ARN="$(cat "${router_nlb_file}" | jq -r '.LoadBalancers[0].LoadBalancerArn')"
else
  echo "Router load balancer already exists"
fi
export ROUTER_NLB_DNS_NAME="$(cat "${router_nlb_file}" | jq -r '.LoadBalancers[0].DNSName')"
echo "Router LB is ${ROUTER_NLB_ARN} with DNS name ${ROUTER_NLB_DNS_NAME}"


tg_http_file="$(mktemp)"
if ! aws elbv2 describe-target-groups --names "${INFRANAME}-${NAMESPACE}-h" > "${tg_http_file}" 2> /dev/null; then
  export HTTP_TG_ARN=""
else
  export HTTP_TG_ARN="$(cat "${tg_http_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
  HTTP_TG_PORT="$(cat "${tg_http_file}" | jq -r '.TargetGroups[0].Port')"
  if [[ "${HTTP_TG_PORT}" != "${ROUTER_NODEPORT_HTTP}" ]]; then
    echo "Found router HTTP load balancer target group, but it does not point to the right port. Deleting."
    aws elbv2 delete-target-group --target-group-arn "${HTTP_TG_ARN}"
    export HTTP_TG_ARN=""
  fi
fi
if [[ -z "${HTTP_TG_ARN}" ]]; then
  echo "Creating target group for router http load balancer"
  aws elbv2 create-target-group --name "${INFRANAME}-${NAMESPACE}-h" \
    --protocol TCP \
    --port ${ROUTER_NODEPORT_HTTP} \
    --vpc-id ${VPC} \
    --health-check-protocol TCP \
    --health-check-enabled \
    --health-check-interval-seconds 10 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --target-type ip > "${tg_http_file}"
  export HTTP_TG_ARN="$(cat "${tg_http_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
  echo "Target group for router HTTP created with ARN ${HTTP_TG_ARN}"
  aws elbv2 add-tags --resource-arns "${HTTP_TG_ARN}" \
    --tags "Key=kubernetes.io/cluster/${INFRANAME},Value=owned"
else
  echo "Target group for router http load balancer already exists"
fi

tg_https_file="$(mktemp)"
if ! aws elbv2 describe-target-groups --names "${INFRANAME}-${NAMESPACE}-s" > "${tg_https_file}" 2> /dev/null; then
  export HTTPS_TG_ARN=""
else
  export HTTPS_TG_ARN="$(cat "${tg_https_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
  HTTPS_TG_PORT="$(cat "${tg_https_file}" | jq -r '.TargetGroups[0].Port')"
  if [[ "${HTTPS_TG_PORT}" != "${ROUTER_NODEPORT_HTTPS}" ]]; then
    echo "Found router HTTPS load balancer target group, but it does not point to the right port. Deleting."
    aws elbv2 delete-target-group --target-group-arn "${HTTPS_TG_ARN}"
    export HTTPS_TG_ARN=""
  fi
fi
if [[ -z "${HTTPS_TG_ARN}" ]]; then
  aws elbv2 create-target-group --name "${INFRANAME}-${NAMESPACE}-s" \
    --protocol TCP \
    --port ${ROUTER_NODEPORT_HTTPS} \
    --vpc-id ${VPC} \
    --health-check-protocol TCP \
    --health-check-enabled \
    --health-check-interval-seconds 10 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --target-type ip > "${tg_https_file}"
  export HTTPS_TG_ARN="$(cat "${tg_https_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
  echo "Target group for router HTTPS created with ARN ${HTTPS_TG_ARN}"
  aws elbv2 add-tags --resource-arns "${HTTPS_TG_ARN}" \
    --tags "Key=kubernetes.io/cluster/${INFRANAME},Value=owned"
else
  echo "Target group for router https load balancer already exists"
fi

router_listener_file="$(mktemp)"
aws elbv2 describe-listeners --load-balancer-arn "${ROUTER_NLB_ARN}" > "${router_listener_file}"
export HTTP_LISTENER_ARN="$(cat "${router_listener_file}" | jq '.Listeners[] | select(.Port==80) | .ListenerArn')"
export HTTPS_LISTENER_ARN="$(cat "${router_listener_file}" | jq '.Listeners[] | select(.Port=443) | .ListenerArn')"

if [[ "${HTTP_LISTENER_ARN}" == "null" ]]; then
  export HTTP_LISTENER_ARN=""
fi

if [[ "${HTTPS_LISTENER_ARN}" == "null" ]]; then
  export HTTPS_LISTENER_ARN=""
fi

if [[ -n "${HTTP_LISTENER_ARN}" ]]; then
  export HTTP_LISTENER_TARGET="$(cat "${router_listener_file}" | jq -r '.Listeners[] | select(.Port==80) | .DefaultActions[0].TargetGroupArn')"
  if [[ "${HTTP_LISTENER_TARGET}" != "${HTTP_TG_ARN}" ]]; then
    echo "Found HTTP router listener, but it does not have the correct target. Removing"
    aws elbv2 delete-listener --listener-arn "${HTTP_LISTENER_ARN}"
    export HTTP_LISTENER_ARN=""
  fi
fi

if [[ -z "${HTTP_LISTENER_ARN}" ]]; then
  echo "Creating http listener for router"
  http_listener_file="$(mktemp)"
  aws elbv2 create-listener --load-balancer-arn "${ROUTER_NLB_ARN}" --protocol TCP --port 80 \
    --default-actions "Type=forward,TargetGroupArn=${HTTP_TG_ARN}" > "${http_listener_file}"
  export HTTP_LISTENER_ARN="$(cat "${http_listener_file}" | jq '.Listeners[] | select(.Port==80) | .ListenerArn')"
  echo "HTTP listener created with ARN ${HTTP_LISTENER_ARN}"
else
  echo "Listener for router HTTP already exists"
fi

if [[ -n "${HTTPS_LISTENER_ARN}" ]]; then
  export HTTPS_LISTENER_TARGET="$(cat "${router_listener_file}" | jq -r '.Listeners[] | select(.Port==443) | .DefaultActions[0].TargetGroupArn')"
  if [[ "${HTTPS_LISTENER_TARGET}" != "${HTTPS_TG_ARN}" ]]; then
    echo "Found HTTPS router listener, but it does not have the correct target. Removing"
    aws elbv2 delete-listener --listener-arn "${HTTPS_LISTENER_ARN}"
    export HTTPS_LISTENER_ARN=""
  fi
fi

if [[ -z "${HTTPS_LISTENER_ARN}" ]]; then
  echo "Creating https listener for router"
  https_listener_file="$(mktemp)"
  aws elbv2 create-listener --load-balancer-arn "${ROUTER_NLB_ARN}" --protocol TCP --port 443 \
    --default-actions "Type=forward,TargetGroupArn=${HTTPS_TG_ARN}" > "${https_listener_file}"
  export HTTPS_LISTENER_ARN="$(cat "${https_listener_file}" | jq '.Listeners[] | select(.Port==443) | .ListenerArn')"
  echo "HTTPS listener created with ARN ${HTTP_LISTENER_ARN}"
else
  echo "Listener for router HTTPS already exists"
fi

change_batch_file="$(mktemp)"
cat <<EOF > "${change_batch_file}"
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.${INGRESS_SUBDOMAIN}",
        "Type": "CNAME",
        "TTL": 30,
        "ResourceRecords": [
          {
            "Value": "${ROUTER_NLB_DNS_NAME}"
          }
        ]
      }
    }
  ]
}
EOF

CHANGE_BATCH="$(cat "${change_batch_file}" | jq -c)"
echo "DNS: Upserting recordset for *.${INGRESS_SUBDOMAIN}"
aws route53 change-resource-record-sets --hosted-zone-id="${PUBLIC_ZONE_ID}" --change-batch "${CHANGE_BATCH}" > /dev/null

cat <<EOF > "${REPODIR}/config_api_ip.sh"
export EXTERNAL_API_IP_ADDRESS="${API_PUBLIC_IP}"
EOF

# Ensure that the workers security group allows access to node ports
sg_file="$(mktemp)"
aws ec2 describe-security-groups --filters Name=tag:Name,Values=${INFRANAME}-worker-sg > "${sg_file}"
SG_ID="$(cat "${sg_file}" | jq -r '.SecurityGroups[0].GroupId')"
NODEPORT_RULE="$(cat "${sg_file}" | jq '.SecurityGroups[0].IpPermissions[] | select(.FromPort==30000) | .IpRanges[] | select(.CidrIp == "10.0.0.0/16")')"
if [[ -z "${NODEPORT_RULE}" ]]; then
  echo "Adding worker security group rule to allow internal access to nodeports"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --ip-permissions 'FromPort=30000,ToPort=32767,IpProtocol=tcp,IpRanges=[{CidrIp=10.0.0.0/16}]'
fi

# Ensure that there is an S3 bucket that will hold the worker ignition data
IGNITION_BUCKET="${INFRANAME}-${NAMESPACE}-ign"
existing_bucket="$(aws s3api list-buckets | jq ".Buckets[] | select(.Name==\"${IGNITION_BUCKET}\")")"
if [[ -z "${existing_bucket}" || "${existing_bucket}" == "null" ]]; then
  echo "Ignition bucket does not exist. Creating one."
  aws s3api create-bucket --bucket "${IGNITION_BUCKET}" --acl public-read
  aws s3api put-bucket-tagging --bucket "${IGNITION_BUCKET}" --tagging "TagSet=[{Key=kubernetes.io/cluster/${INFRANAME},Value=owned}]"
fi
echo "Copying bootstrap ignition to bucket ${IGNITION_BUCKET}"
aws s3 cp ${REPODIR}/ignition-generator/final.ign s3://${IGNITION_BUCKET}/final.ign --acl public-read

# Create a bootstrap ignition that points to the final.ign in the S3 bucket
cat <<EOF > "${REPODIR}/machine-api/machine-user-data.ign"
{"ignition":{"config":{"append":[{"source":"https://${IGNITION_BUCKET}.s3.amazonaws.com/final.ign","verification":{}}]},"security":{},"timeouts":{},"version":"2.2.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}
EOF

# Create a machineset for the user cluster
machineset_json="$(mktemp)"
machineset_name="$(oc get machineset -n openshift-machine-api | grep "${INFRANAME}-worker-${AZ}" | awk '{ print $1 }')"
oc get machineset "${machineset_name}" -n openshift-machine-api -o json > "${machineset_json}"
worker_ms_name="${INFRANAME}-${NAMESPACE}-worker"
machineset_xform="\
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
.spec.template.spec.providerSpec.value.userDataSecret.name=\"${NAMESPACE}-worker-user-data\"|\
.spec.template.spec.providerSpec.value += {loadBalancers:[{name:\"${ROUTERLBNAME}\",type:\"network\"}]}"

cat "${machineset_json}" | jq "${machineset_xform}" > "${REPODIR}/machine-api/machineset.json"

pushd "${REPODIR}/machine-api"
./render.sh
popd
