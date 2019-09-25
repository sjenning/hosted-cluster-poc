#/bin/bash

set -ex

source config.sh

mkdir -p pki
cd pki

function generate_client_key_cert() {
  ca=$1
  file=$2
  user=$3
  org=$4
  hostname="$5"

  if [ -f "${file}.pem" ]; then return 0; fi

  cat > ${file}-csr.json <<EOF
  {
    "CN": "${user}",
    "key": {
      "algo": "rsa",
      "size": 2048
    },
    "names": [
      {
        "C": "US",
        "L": "Austin",
        "O": "${org}",
        "OU": "Kubernetes",
        "ST": "Texas"
      }
    ]
  }
EOF

  cfssl gencert \
    -ca=${ca}.pem \
    -ca-key=${ca}-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    -hostname="${hostname}" \
    ${file}-csr.json | cfssljson -bare ${file}

    rm ${file}-csr.json ${file}.csr
}

function generate_client_kubeconfig() {
  ca=$1
  file=$2
  name=$3
  server="kube-apiserver:6443"

  if [ ! -z "${6}" ]; then
    server="${6}"
  fi

  if [ -f "${file}.kubeconfig" ]; then return 0; fi

  generate_client_key_cert "${1}" "${2}" "${3}" "${4}" "${5}"

  kubectl config set-cluster default \
    --certificate-authority=root-ca.pem \
    --embed-certs=true \
    --server=https://${server} \
    --kubeconfig=${file}.kubeconfig

  kubectl config set-credentials ${file} \
    --client-certificate=${file}.pem \
    --client-key=${file}-key.pem \
    --embed-certs=true \
    --kubeconfig=${file}.kubeconfig

  kubectl config set-context default \
    --cluster=default \
    --user=${file} \
    --kubeconfig=${file}.kubeconfig

  kubectl config use-context default --kubeconfig=${file}.kubeconfig

  rm ${file}.pem ${file}-key.pem
}

function generate_ca() {
  name="$1"

  if [ -f "${name}.pem" ]; then return 0; fi

  cat <<EOF | cfssl gencert -initca - | cfssljson -bare ${name}
  {
    "CN": "${name}",
    "key": {
      "algo": "rsa",
      "size": 2048
    },
    "names": [
      {
        "C": "US",
        "L": "Austin",
        "O": "Kubernetes",
        "OU": "root-ca",
        "ST": "Texas"
      }
    ]
  }
EOF
}

function generate_intermediate_ca() {
  rootca="$1"
  name="$2"

  if [ -f "${name}.pem" ]; then return 0; fi

  cat <<EOF | cfssl gencert -initca - | cfssljson -bare ${name}
  {
    "CN": "${name}",
    "key": {
      "algo": "rsa",
      "size": 2048
    },
    "names": [
      {
        "C": "US",
        "L": "Austin",
        "O": "Kubernetes",
        "OU": "root-ca",
        "ST": "Texas"
      }
    ]
  }
EOF

  cat > ${name}-config.json <<EOF 
  {
    "signing": {
      "default": {
        "usages": ["digital signature","cert sign","crl sign","signing"],
        "expiry": "8760h",
        "ca_constraint": {"is_ca": true, "max_path_len":0, "max_path_len_zero": true}
      }
    }
  }
EOF

  cfssl sign -ca ${rootca}.pem -ca-key ${rootca}-key.pem -config ${name}-config.json ${name}.csr | cfssljson -bare ${name}

  rm ${name}.csr ${name}-config.json
}

function generate_secret() {
  file=$2

  if [ -f "${file}-tls.yaml" ]; then return 0; fi

  generate_client_key_cert "${1}" "${2}" "${3}" "${4}" "${5}"

  export SECRET_NAME=${file}
  export SECRET_CERT=$(cat ${file}.pem | base64 | tr -d '\n')
  export SECRET_KEY=$(cat ${file}-key.pem | base64 | tr -d '\n')

  envsubst < ../templates/secret-tls-template.yaml > ${file}-tls.yaml
}

# generate ca-config
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

# generate CAs
generate_ca "root-ca"
generate_ca "cluster-signer"

# admin kubeconfig
generate_client_kubeconfig "root-ca" "admin" "system:admin" "system:masters" "" "${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT}"

# kubelet bootstrapper kubeconfig
generate_client_kubeconfig "cluster-signer" "kubelet-bootstrap" "system:bootstrapper" "system:bootstrappers" "" "${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT}"

# service client admin kubeconfig
generate_client_kubeconfig "root-ca" "service-admin" "system:admin" "system:masters" "kube-apiserver"

# kube-controller-manager
generate_client_kubeconfig "root-ca" "kube-controller-manager" "system:admin" "system:masters" "kube-apiserver"
if [ ! -e "service-account-key.pem" ]; then 
  openssl genrsa -out service-account-key.pem 2048
  openssl rsa -in service-account-key.pem -pubout > service-account.pem
fi

# kube-proxy
generate_client_kubeconfig "root-ca" "kube-proxy" "system:kube-proxy" "kubernetes" "" "${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT}"

# kube-scheduler
generate_client_kubeconfig "root-ca" "kube-scheduler" "system:admin" "system:masters"

# kube-apiserver
generate_client_key_cert "root-ca" "kube-apiserver-server" "kubernetes" "kubernetes" "${EXTERNAL_API_DNS_NAME},172.31.0.1,172.20.0.1,kubernetes,kubernetes.default.svc,kubernetes.default.svc.cluster.local,kube-apiserver,kube-apiserver.${NAMESPACE}.svc,kube-apiserver.${NAMESPACE}.svc.cluster.local"
generate_client_key_cert "root-ca" "kube-apiserver-kubelet" "system:kube-apiserver" "kubernetes"
generate_client_key_cert "root-ca" "kube-apiserver-aggregator-proxy-client" "system:openshift-aggregator" "kubernetes"

# etcd
generate_client_key_cert "root-ca" "etcd-client" "kubernetes" "kubernetes"
generate_client_key_cert "root-ca" "etcd-server" "etcd-server" "kubernetes" "*.etcd.${NAMESPACE}.svc,etcd-client.${NAMESPACE}.svc,etcd,etcd-client,localhost"
generate_client_key_cert "root-ca" "etcd-peer" "etcd-peer" "kubernetes" "*.etcd.${NAMESPACE}.svc,*.etcd.${NAMESPACE}.svc.cluster.local"

# openshift-apiserver
generate_client_key_cert "root-ca" "openshift-apiserver-server" "openshift" "openshift" "openshift-apiserver,openshift-apiserver.${NAMESPACE}.svc,openshift-controller-manager.${NAMESPACE}.svc.cluster.local,openshift-apiserver.default.svc,openshift-apiserver.default.svc.cluster.local"

# openshift-controller-manager
generate_client_key_cert "root-ca" "openshift-controller-manager-server" "openshift" "openshift" "openshift-controller-manager,openshift-controller-manager.${NAMESPACE}.svc,openshift-controller-manager.${NAMESPACE}.svc.cluster.local"

cat root-ca.pem cluster-signer.pem > combined-ca.pem

rm -f *.csr
