#!/usr/bin/env bash

cd "$(dirname "$0")" || exit 0

LONGHORN_VERSION=1.3.2

chartName=$(helm list -n longhorn-system -o json | jq '.[0].name' | grep -v null)
if [ -n "$chartName" ]; then
  echo "Longhorn v${LONGHORN_VERSION} already installed. Skip."
  exit 0
fi

# Install Longhorn dependencies on all nodes and wait
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-iscsi-installation.yaml
echo "Waiting for iscsi installation on all nodes..."
kubectl wait --for condition=ready pod -l app=longhorn-iscsi-installation
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-iscsi-installation.yaml

kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-nfs-installation.yaml
echo "Waiting for nfs-common installation on all nodes..."
kubectl wait --for condition=ready pod -l app=longhorn-nfs-installation
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-nfs-installation.yaml

# Check nodes have all dependencies for Longhorn
multipass exec master -- curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/scripts/environment_check.sh | bash
exitCode=$?
if [[ $exitCode -ne 0 ]]; then
  echo "Longhorn dependencies not met. Exit code: $exitCode"
  exit 1
fi

# Install
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version $LONGHORN_VERSION

# Wait for longhorn pods to be ready
echo "Waiting for Longhorn pods to be ready..."
kubectl wait --for condition=ready pod -l app.kubernetes.io/name=longhorn -n longhorn-system

kubectl apply -f ./longhorn-ui-ingress.yaml

echo "Longhorn v${LONGHORN_VERSION} installed."