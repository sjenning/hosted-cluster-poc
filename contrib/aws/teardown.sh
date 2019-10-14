#!/bin/bash

set -eu

function get_infra_name()
{
  local __infra_name_var="${1}"

  local infra_name=""
  infra_name="$(oc get infrastructure/cluster -o jsonpath='{ .status.infrastructureName }')"

  eval $__infra_name_var="'${infra_name}'"
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

function remove_cname_record()
{
  local zone_id="${1}"
  local domain="${2}"
  
  local recordsets_file="$(mktemp)"
  local value=""
  local next_token=""
  while true; do
    if [[ -z "${next_token}" ]]; then
      aws route53 list-resource-record-sets --hosted-zone-id "${zone_id}" > "${recordsets_file}"
    else
      aws route53 list-resource-record-sets --hosted-zone-id "${zone_id}" --starting-token "${next_token}" > "${recordsets_file}"
    fi
    value="$(cat ${recordsets_file} | jq -r ".ResourceRecordSets[] | select(.Name==\"${domain}\") | .ResourceRecords[0].Value")"
    if [[ value=="null" ]]; then
      value=""
    fi
    if [[ -n "${value}" ]]; then
      local change_batch_file="$(mktemp)"
      cat <<EOF > "${change_batch_file}"
{
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "${domain}",
        "Type": "CNAME",
        "TTL": 30,
        "ResourceRecords": [
          {
            "Value": "${value}"
          }
        ]
      }
    }
  ]
}
EOF
      local change_batch="$(cat "${change_batch_file}" | jq -c)"
      aws route53 change-resource-record-sets --hosted-zone-id="${zone_id}" --change-batch "${change_batch}" > /dev/null
      break
    else
      next_token="$(cat "${recordsets_file}" | jq -r ".NextToken")"
      if [[ -z "${next_token}" || "${next_token}" == "null" ]]; then
        break
      fi
    fi
  done
}

function remove_nlb() 
{
  local nlb_name="${1}"

  local nlb_file="$(mktemp)"
  local arn=""
  if ! aws elbv2 describe-load-balancers --names "${nlb_name}" > "${nlb_file}" 2> /dev/null; then
    arn=""
  else
    arn="$(cat ${nlb_file} | jq -r '.LoadBalancers[0].LoadBalancerArn')"
  fi

  if [[ -n "${arn}" ]]; then
    aws elbv2 delete-load-balancer --load-balancer-arn "${arn}"
  fi
}

function remove_target_group()
{
  local tg_name="${1}"

  local tg_file="$(mktemp)"
  local arn=""

  if ! aws elbv2 describe-target-groups --names "${tg_name}" > "${tg_file}" 2> /dev/null; then
    arn=""
  else
    arn="$(cat "${tg_file}" | jq -r '.TargetGroups[0].TargetGroupArn')"
    if [[ "${arn}" == "null" ]]; then
      arn=""
    fi
  fi

  if [[ -n "${arn}" ]]; then
    aws elbv2 delete-target-group --target-group-arn "${arn}"
  fi
}

function remove_eip()
{
  local eip_name="${1}"

  local address_file="$(mktemp)"
  while true; do
    aws ec2 describe-addresses --filter "Name=tag:Name,Values=${eip_name}" > "${address_file}"
    local allocation_id="$(cat "${address_file}" | jq -r '.Addresses[0].AllocationId')"
    if [[ -n "${allocation_id}" && "${allocation_id}" != "null" ]]; then
      local nic_id="$(cat "${address_file}" | jq -r '.Addresses[0].NetworkInterfaceId')"
      if [[ -n "${nic_id}" && "${nic_id}" != "null" ]]; then
        # Address has not been released yet, keep waiting
        sleep 20
        continue
      fi
      aws ec2 release-address --allocation-id "${allocation_id}"
      break
    else
      # Address doesn't exist, we're done
      break
    fi
  done
}

function remove_worker_machineset()
{
  local name="${1}"

  oc delete machineset "${name}" -n openshift-machine-api --ignore-not-found
}

function remove_bucket()
{
  local name="${1}"

  if aws s3api head-bucket --bucket ${name} &> /dev/null; then
    aws s3 rb s3://${name} --force
  fi
}

REPODIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/../.."
source "${REPODIR}/config.sh"

get_infra_name INFRANAME
get_zone_id "${PARENT_DOMAIN}" ZONE_ID

# Remove API load balancer
APILB="${INFRANAME}-${NAMESPACE}-api"
remove_cname_record "${ZONE_ID}" "${EXTERNAL_API_DNS_NAME}."
remove_nlb "${APILB}"
remove_target_group "${APILB}"
remove_eip "${APILB}"

# Remove router load balancer
ROUTERLB="${INFRANAME}-${NAMESPACE}-apps"
remove_cname_record "${ZONE_ID}" "\\\\053.${INGRESS_SUBDOMAIN}."
remove_nlb "${ROUTERLB}"
remove_target_group "${INFRANAME}-${NAMESPACE}-h"
remove_target_group "${INFRANAME}-${NAMESPACE}-s"

remove_worker_machineset "${INFRANAME}-${NAMESPACE}-worker"

remove_bucket "${INFRANAME}-${NAMESPACE}-ign"
