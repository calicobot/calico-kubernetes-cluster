# Clone kubernetes if necessary
if ! ls | grep kubernetes; then
  git clone -b release-1.1 https://github.com/kubernetes/kubernetes.git
  cd kubernetes
  git remote add casey https://github.com/caseydavenport/kubernetes.git
  git fetch --all
  cd ..
fi

# Build binaries if necessary
if ! ls kubernetes| grep "_output"; then
  cd kubernetes
  git checkout release-1.1
  docker pull golang:1.4
  make quick-release
  cd ..
fi

# Checkout Calico Vagrant Provisioner branch
cd kubernetes
git fetch --all
git checkout casey/calico-vagrant-integration
cd ..

cd ~/jobs/Calico-Kubernetes-PR/workspace/dist
python3 -m http.server 8472 &
cd ~/jobs/Kubernetes-Cluster/workspace

export ARTIFACT_URL=http://127.0.0.1:8472/calico_kubernetes
wget $ARTIFACT_URL
export ARTIFACT_SHA=$(sha512sum ./calico_kubernetes)
sudo rm calico_kubernetes
sed -i "s/https:\/\/github.com\/projectcalico\/calico-kubernetes\/releases\/download\/v0.6.1\/calico_kubernetes/${ARTIFACT_URL}/" kubernetes/cluster/saltbase/salt/calico/node.sls
sed -i "s/38d1ae62cf2a8848946e0d7442e91bcdefd3ac8c2167cdbc6925c25e5eb9c8b60d1f348eb861de34f4167ef6e19842c37b18c5fc3804cfdca788a65d625c5502/${ARTIFACT_SHA}/" kubernetes/cluster/saltbase/salt/calico/node.sls

NUM_MINIONS=2 KUBE_VERSION=v1.1.1 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico kubernetes/cluster/kube-up.sh

WORKERS=2; sed -i "s/NUM_MINIONS=[0-9]/NUM_MINIONS=${WORKERS}/" kubernetes/hack/conformance-test.sh
KUBECONFIG=/var/lib/jenkins/.kube/config kubernetes/hack/conformance-test.sh 2>&1 | tee conformance.$(date +%FT%T%z).log

NUM_MINIONS=2 KUBE_VERSION=v1.1.1 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico kubernetes/cluster/kube-down.sh

# Close calico_kubernetes http server
ps axf | grep "python3 -m http.server 8472" | grep -v grep | awk '{print "kill -9 " $1}' | sh
