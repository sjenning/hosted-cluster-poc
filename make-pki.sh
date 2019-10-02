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
        "O": "${org}"
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
    }
  }
EOF
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
generate_ca "ingress-signer"

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

# kube-scheduler
generate_client_kubeconfig "root-ca" "kube-scheduler" "system:admin" "system:masters"

# kube-apiserver
generate_client_key_cert "root-ca" "kube-apiserver-server" "kubernetes" "kubernetes" "${EXTERNAL_API_DNS_NAME},172.31.0.1,${EXTERNAL_API_IP_ADDRESS},kubernetes,kubernetes.default.svc,kubernetes.default.svc.cluster.local,kube-apiserver,kube-apiserver.${NAMESPACE}.svc,kube-apiserver.${NAMESPACE}.svc.cluster.local"
generate_client_key_cert "root-ca" "kube-apiserver-kubelet" "system:kube-apiserver" "kubernetes"
generate_client_key_cert "root-ca" "kube-apiserver-aggregator-proxy-client" "system:openshift-aggregator" "kubernetes"

# etcd
generate_client_key_cert "root-ca" "etcd-client" "etcd-client" "kubernetes"
generate_client_key_cert "root-ca" "etcd-server" "etcd-server" "kubernetes" "*.etcd.${NAMESPACE}.svc,etcd-client.${NAMESPACE}.svc,etcd,etcd-client,localhost"
generate_client_key_cert "root-ca" "etcd-peer" "etcd-peer" "kubernetes" "*.etcd.${NAMESPACE}.svc,*.etcd.${NAMESPACE}.svc.cluster.local"

# openshift-apiserver
generate_client_key_cert "root-ca" "openshift-apiserver-server" "openshift-apiserver" "openshift" "openshift-apiserver,openshift-apiserver.${NAMESPACE}.svc,openshift-controller-manager.${NAMESPACE}.svc.cluster.local,openshift-apiserver.default.svc,openshift-apiserver.default.svc.cluster.local"

# openshift-controller-manager
generate_client_key_cert "root-ca" "openshift-controller-manager-server" "openshift-controller-manager" "openshift" "openshift-controller-manager,openshift-controller-manager.${NAMESPACE}.svc,openshift-controller-manager.${NAMESPACE}.svc.cluster.local"

# openshift-ingress
rm -f ingress-wildcard*
generate_client_key_cert "ingress-signer" "ingress-wildcard" "*.${INGRESS_SUBDOMAIN}" "openshift" "*.${INGRESS_SUBDOMAIN}"
cat ingress-signer.pem >> ingress-wildcard.pem

cat root-ca.pem cluster-signer.pem ingress-signer.pem > combined-ca.pem

rm -f *.csr
