#!/usr/bin/env bash

VAULT_VERSION=1.11.3
CHART_VERSION=0.22.0
cd "$(dirname "$0")" || exit 0

chartName=$(helm list -n vault -o json | jq '.[0].name' | grep -v null)
if [ -n "$chartName" ]; then
  echo "Vault v${VAULT_VERSION} already installed. Skip."
  exit 0
fi

# Check if vault cli is installed to configure issuer
if ! command -v vault /dev/null
then
  echo "Vault not found. Please install here: https://cert-manager.io/docs/reference/cmctl/#installation"
  exit 1
fi

# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
kubectl create namespace vault
helm install vault hashicorp/vault -f vault-chart-values.yaml --namespace vault --version $CHART_VERSION

kubectl apply -f vault-ingress.yaml

# Wait for vault pod to be ready
echo "Waiting for Vault pod to be created..."
kubectl wait --for=jsonpath='{.status.phase}'=Pending pod/vault-0 -n vault

# Add cert to local truststore
./get-and-convert-root-cert.sh
sudo trust anchor --store home-dot-com.crt

echo "Waiting for Vault pod to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 -n vault

# Setup Vault issuer
./setup-vault-issuer.sh

echo "Vault v${VAULT_VERSION} installed."