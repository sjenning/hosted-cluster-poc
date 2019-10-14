function encode() {
  cat ${1} | base64 | tr -d '\n' | tr -d '\r'
}

function fetch_release_pullspecs() {
    local repodir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/.."
    if [[ -z "${RELEASE_PULLSPECS}" ]]; then
      >&2 echo "Release pull specs not set"
      exit 1
    fi
    oc adm release info --registry-config "${repodir}/pull-secret" "${RELEASE_IMAGE}" --pullspecs > "${RELEASE_PULLSPECS}"
}

function image_for() {
  local name="${1}"

  local pullspecs="${RELEASE_PULLSPECS:-}"
  if [[ -z "${pullspecs}" ]]; then
    export RELEASE_PULLSPECS="$(mktemp)"
    fetch_release_pullspecs
  fi
  cat "${RELEASE_PULLSPECS}" | grep "^  ${name}\\s" | awk '{ print $2 }'
}
