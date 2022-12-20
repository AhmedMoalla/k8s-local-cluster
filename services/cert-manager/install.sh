#!/usr/bin/env bash
CERTMANAGER_VERSION=1.9.1

chartName=$(helm list -n cert-manager -o json | jq '.[0].name' | grep -v null)
if [ -n "$chartName" ]; then
  echo "Cert-Manager v${CERTMANAGER_VERSION} already installed. Skip."
  exit 0
fi

# Check if cmctl is installed to verify installation later on
if ! command -v cmctl /dev/null
then
  echo "Cmctl not found. Please install here: https://cert-manager.io/docs/reference/cmctl/#installation"
  exit 1
fi

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager \
  --set installCRDs=true \
  --namespace cert-manager \
  --create-namespace \
  --version v${CERTMANAGER_VERSION}

# Check installation
cmctl check api --wait=2m

echo "Cert-Manager v${CERTMANAGER_VERSION} installed."
