#/bin/bash

set -ex

BASEDIR=pki
NAMESPACE=${NAMESPACE}

mkdir -p $BASEDIR
cd $BASEDIR

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
  server="kubernetes.${NAMESPACE}.svc"

  if [ ! -z "${6}" ]; then
    server="${6}"
  fi

  if [ -f "${file}.kubeconfig" ]; then return 0; fi

  generate_client_key_cert "${1}" "${2}" "${3}" "${4}" "${5}"

  kubectl config set-cluster default \
    --certificate-authority=${ca}.pem \
    --embed-certs=true \
    --server=https://${server}:6443 \
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
        "OU": "CA",
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
        "OU": "CA",
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
generate_ca "ca"

generate_client_kubeconfig "ca" "admin" "system:admin" "system:masters" "tugboat" "tugboat.lab.variantweb.net"

#NODES="tugboat"
#for node in ${NODES}; do
#generate_client_kubeconfig "ca" "kubelet" "system:node:${node}" "system:nodes"
#generate_client_key_cert "ca" "kubelet-server" "system:node:${node}" "system:nodes" "${node},127.0.0.1"
#done

generate_client_kubeconfig "ca" "kube-controller-manager" "system:kube-controller-manager" "kubernetes"
if [ ! -e "service-account-key.pem" ]; then 
  openssl genrsa -out service-account-key.pem 2048
  openssl rsa -in service-account-key.pem -pubout > service-account.pem
fi

# kube-proxy
generate_client_kubeconfig "ca" "kube-proxy" "system:kube-proxy" "kubernetes"

# kube-scheduler
generate_client_kubeconfig "ca" "kube-scheduler" "system:kube-scheduler" "kubernetes"

# kube-apiserver
generate_client_key_cert "ca" "kube-apiserver-server" "kubernetes" "kubernetes" "api-hosted.lab.variantweb.net,127.0.0.1,172.30.0.1,kubernetes,kubernetes.{$NAMESPACE},kubernetes.{$NAMESPACE}.svc,kubernetes.{$NAMESPACE}.svc.cluster.local"
generate_client_key_cert "ca" "kube-apiserver-kubelet" "system:kube-apiserver" "kubernetes"

# etcd
generate_client_key_cert "ca" "etcd-client" "kubernetes" "kubernetes"
generate_client_key_cert "ca" "etcd-server" "etcd-server" "kubernetes" "*.etcd.${NAMESPACE}.svc,etcd-client.${NAMESPACE}.svc,etcd,etcd-client,localhost"
generate_client_key_cert "ca" "etcd-peer" "etcd-peer" "kubernetes" "*.etcd.${NAMESPACE}.svc,*.etcd.${NAMESPACE}.svc.cluster.local"

rm -f *.csr
