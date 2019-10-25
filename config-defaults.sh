REPODIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${REPODIR}/config.sh

export POD_NETWORK="${POD_NETWORK:-10.124.0.0}"
export POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-${POD_NETWORK}/14}"
export POD_NETWORK_MASK="${POD_NETWORK_MASK:-255.252.0.0}"

export SERVICE_NETWORK_PREFIX="${SERVICE_NETWORK_PREFIX:-172.31}"
export SERVICE_NETWORK="${SERVICE_NETWORK:-${SERVICE_NETWORK_PREFIX}.0.0}"
export SERVICE_NETWORK_CIDR="${SERVICE_NETWORK_CIDR:-${SERVICE_NETWORK}/16}"
export SERVICE_NETWORK_MASK="${SERVICE_NETWORK_MASK:-255.255.0.0}"

export REPLICAS="${REPLICAS:-1}"
