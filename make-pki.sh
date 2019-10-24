#/bin/bash

set -e

source config-defaults.sh

mkdir -p pki
cd pki
cp ../pki-cert-templates/ca-config.json ./

function generate_client_key_cert() {
  ca=$1
  file=$2
  user=$3
  org=$4
  export user
  export org

  if [ -f "${file}.pem" ]; then return 0; fi
  envsubst < ../pki-cert-templates/${file}-csr.json > ${file}-csr.json
  cat ${file}-csr.json
  cat ca-config.json
  cfssl gencert \
    -ca=${ca}.pem \
    -ca-key=${ca}-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    ${file}-csr.json | cfssljson -bare ${file}

  rm ${file}-csr.json ${file}.csr
}

function generate_client_kubeconfig() {
  ca=$1
  file=$2
  name=$3
  server="kube-apiserver:6443"

  if [ ! -z "${5}" ]; then
    server="${5}"
  fi

  if [ -f "${file}.kubeconfig" ]; then return 0; fi

  generate_client_key_cert "${1}" "${2}" "${3}" "${4}"

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

# generate CAs
generate_ca "root-ca"
generate_ca "cluster-signer"

# admin kubeconfig
generate_client_kubeconfig "root-ca" "admin" "system:admin" "system:masters" "${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT}"

# kubelet bootstrapper kubeconfig
generate_client_kubeconfig "cluster-signer" "kubelet-bootstrap" "system:bootstrapper" "system:bootstrappers" "${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT}"

# service client admin kubeconfig
generate_client_kubeconfig "root-ca" "service-admin" "system:admin" "system:masters"

# kube-controller-manager
generate_client_kubeconfig "root-ca" "kube-controller-manager" "system:admin" "system:masters"
if [ ! -e "service-account-key.pem" ]; then 
  openssl genrsa -out service-account-key.pem 2048
  openssl rsa -in service-account-key.pem -pubout > service-account.pem
fi

# kube-scheduler
generate_client_kubeconfig "root-ca" "kube-scheduler" "system:admin" "system:masters"

# kube-apiserver
generate_client_key_cert "root-ca" "kube-apiserver-server" "kubernetes" "kubernetes"
generate_client_key_cert "root-ca" "kube-apiserver-kubelet" "system:kube-apiserver" "kubernetes"
generate_client_key_cert "root-ca" "kube-apiserver-aggregator-proxy-client" "system:openshift-aggregator" "kubernetes"

# etcd
generate_client_key_cert "root-ca" "etcd-client" "etcd-client" "kubernetes"
generate_client_key_cert "root-ca" "etcd-server" "etcd-server" "kubernetes"
generate_client_key_cert "root-ca" "etcd-peer" "etcd-peer" "kubernetes"

# openshift-apiserver
generate_client_key_cert "root-ca" "openshift-apiserver-server" "openshift-apiserver" "openshift"

# openshift-controller-manager
generate_client_key_cert "root-ca" "openshift-controller-manager-server" "openshift-controller-manager" "openshift"

cat root-ca.pem cluster-signer.pem > combined-ca.pem

rm -f *.csr

# openvpn assets
generate_ca "openvpn-ca"
generate_client_key_cert "openvpn-ca" "openvpn-server" "server" "kubernetes"
generate_client_key_cert "openvpn-ca" "openvpn-kube-apiserver-client" "kube-apiserver" "kubernetes"
generate_client_key_cert "openvpn-ca" "openvpn-worker-client" "worker" "kubernetes"
if [ ! -e "openvpn-dh.pem" ]; then
  # this might be slow, lots of entropy required
  openssl dhparam -out openvpn-dh.pem 2048
fi
