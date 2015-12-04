# Clone kubernetes if necessary
if ! ls | grep kubernetes; then
  git clone -b release-1.1 https://github.com/kubernetes/kubernetes.git
  cd kubernetes
  git remote add casey https://github.com/caseydavenport/kubernetes.git
  git fetch origin pull/7245/head:calico-vagrant
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
git reset --hard origin/master
git checkout calico-vagrant ./cluster/

# Host new binary
mkdir server && cd server
cp -f ~/jobs/Calico-Kubernetes-Build/workspace/dist/calico_kubernetes ./
python3 -m http.server 8472 &
cd ..

# Get URL and SHA512 of binary
export ARTIFACT_URL=http://127.0.0.1:8472/calico_kubernetes
wget $ARTIFACT_URL
export ARTIFACT_SHA=$(sha512sum ./calico_kubernetes | cut -f 1 -d " ")
rm calico_kubernetes

# Replace binary/shaw in salt files
export OLD_URL=https://github.com/projectcalico/calico-kubernetes/releases/download/v0.6.1/calico_kubernetes
export OLD_SHA=38d1ae62cf2a8848946e0d7442e91bcdefd3ac8c2167cdbc6925c25e5eb9c8b60d1f348eb861de34f4167ef6e19842c37b18c5fc3804cfdca788a65d625c5502
sed -i "s|$OLD_URL|$ARTIFACT_URL|g" ./cluster/saltbase/salt/calico/node.sls
sed -i "s|$OLD_SHA|$ARTIFACT_SHA|g" ./cluster/saltbase/salt/calico/node.sls

# kube-down first to purge any orphaned boxes
NUM_NODES=2 KUBE_VERSION=v1.1.1 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico ./cluster/kube-down.sh
NUM_NODES=2 KUBE_VERSION=v1.1.1 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico ./cluster/kube-up.sh

# Run Conformance
WORKERS=2; sed -i "s/NUM_NODES=[0-9]/NUM_NODES=${WORKERS}/" ./hack/conformance-test.sh
KUBECONFIG=/var/lib/jenkins/.kube/config ./hack/conformance-test.sh 2>&1 | tee conformance.$(date +%FT%T%z).log

# Clean-up
NUM_NODES=2 KUBE_VERSION=v1.1.1 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico ./cluster/kube-down.sh
ps axf | grep "python3 -m http.server 8472" | grep -v grep | awk '{print "kill -9 " $1}' | sh
