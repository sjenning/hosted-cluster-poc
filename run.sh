# target your kubeconfig at an IKS cluster
export KUBECONFIG=/Users/krglosse@us.ibm.com/.bluemix/plugins/container-service/clusters/ian-test-12/kube-config-wdc06-ian-test-12.yml
export NAMESPACE=kodie-test-1
DOMAIN=$(ibmcloud ks cluster get bmku2n6w02ijgkck3i20 | grep Subdomain | awk '{print $3}')

export EXTERNAL_API_IP_ADDRESS="172.20.0.1"

cp config.sh.iks_example config.sh
chmod +x config.sh
sed -i "s/managed.example.com/$DOMAIN/g" config.sh
sed -i "s/example.com/$DOMAIN/g" config.sh

# Assuming your IKS cluster has the default service ip range of 172.21/16
sed -i "s/172.30.0.20/172.21.0.20/g" openshift-apiserver/openshift-apiserver-service.yaml
sed -i "s/172.30.0.20/172.21.0.20/g" openshift-apiserver/openshift-apiserver-user-endpoint.yaml


./install-openshift.sh
