export BUILD_ROOT=$PWD

# Clone kubernetes if necessary
if ! ls $BUILD_ROOT/cluster | grep kubernetes; then
  cd $BUILD_ROOT/cluster
  git clone -b release-1.1 https://github.com/kubernetes/kubernetes.git
  cd $BUILD_ROOT/cluster/kubernetes
  git remote add casey https://github.com/caseydavenport/kubernetes.git
  git fetch origin pull/7245/head:calico-vagrant
  cd $BUILD_ROOT/
fi

# Build binaries if necessary
if ! ls $BUILD_ROOT/cluster/kubernetes| grep "_output"; then
  cd $BUILD_ROOT/cluster/kubernetes
  git checkout origin/release-1.1
  docker pull golang:1.4
  make quick-release
  cd $BUILD_ROOT/
fi

# Checkout Calico Vagrant Provisioner branch
cd $BUILD_ROOT/cluster/kubernetes
git fetch origin pull/7245/head:calico-vagrant
git fetch casey calico-vagrant-integration

git reset --hard origin/release-1.1
git checkout calico-vagrant ./cluster/

# Host new binary
cd $BUILD_ROOT/calico-kubernetes/dist
python3 -m http.server 8472 &

# Replace binary/sha in salt files
export ARTIFACT_URL=http://destroyer:8472/calico
export ARTIFACT_SHA=$(sha512sum $BUILD_ROOT/calico-kubernetes/dist/calico | cut -f 1 -d " ")
export OLD_URL=https://github.com/projectcalico/calico-kubernetes/releases/download/v0.6.1/calico_kubernetes
export OLD_SHA=38d1ae62cf2a8848946e0d7442e91bcdefd3ac8c2167cdbc6925c25e5eb9c8b60d1f348eb861de34f4167ef6e19842c37b18c5fc3804cfdca788a65d625c5502
sed -i "s|$OLD_URL|$ARTIFACT_URL|g" $BUILD_ROOT/cluster/kubernetes/cluster/saltbase/salt/calico/node.sls
sed -i "s|$OLD_SHA|$ARTIFACT_SHA|g" $BUILD_ROOT/cluster/kubernetes/cluster/saltbase/salt/calico/node.sls

# kube-down first to purge any orphaned boxes
cd $BUILD_ROOT/cluster/kubernetes
NUM_NODES=2 NUM_MINIONS=2 KUBE_VERSION=v1.1.2 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico ./cluster/kube-down.sh
NUM_NODES=2 NUM_MINIONS=2 KUBE_VERSION=v1.1.2 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico ./cluster/kube-up.sh

# Run Conformance on 2 Nodes (some revisions of the script use `minions`)
WORKERS=2; sed -i "s/NUM_NODES=[0-9]/NUM_NODES=${WORKERS}/" ./hack/conformance-test.sh
WORKERS=2; sed -i "s/NUM_MINIONS=[0-9]/NUM_MINIONS=${WORKERS}/" ./hack/conformance-test.sh
KUBECONFIG=/var/lib/jenkins/.kube/config ./hack/conformance-test.sh 2>&1 | tee conformance.log

# Parse number of failures
export expected_failures=10
export failures=$(tail -n 150 conformance.log | grep Summarizing | awk '{print $2}')
echo "Conformance Tests found $failures failures, expected $expected_failures"

# Save the log
if ! ls $BUILD_ROOT/ | grep conformance_logs; then mkdir $BUILD_ROOT/conformance_logs; fi
mv conformance.log $BUILD_ROOT/conformance_logs/conformance.$(date +%FT%T%z).log

# Clean-up
NUM_NODES=2 NUM_MINIONS=2 KUBE_VERSION=v1.1.2 KUBERNETES_PROVIDER=vagrant NETWORK_PROVIDER=calico ./cluster/kube-down.sh
ps axf | grep "python3 -m http.server 8472" | grep -v grep | awk '{print "kill -9 " $1}' | sh

exit $((failures!=expected_failures))