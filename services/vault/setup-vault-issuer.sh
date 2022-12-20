#!/usr/bin/env bash
set -e
# Run this script after installing cert-manager and vault.

# Port forward internal vault service in background and suppress output
kubectl port-forward -n vault svc/vault 8200:8200 &
# Get PID of port-forward process
portForwardPid=$!
echo "Port forward PID: $portForwardPid"
# Wait for port-forward to be ready
sleep 5

# Setup VAULT_ADDR environment variable
export VAULT_ADDR="http://localhost:8200"

# Initialize Vault
vault operator init -key-shares=1 -key-threshold=1 -format=json >init-keys.json

# Setup VAULT_TOKEN environment variable
VAULT_TOKEN="$(jq -r ".root_token" init-keys.json)"
export VAULT_TOKEN

# Copy and Keep the Unseal keys and the initial root token
# Unseal Vault
vault operator unseal "$(jq -r ".unseal_keys_b64[]" init-keys.json)"

# Enable PKI Engine
vault secrets enable pki
# Configure the max lease time-to-live (TTL)
vault secrets tune -max-lease-ttl=8760h pki

# Create root certificate for local domain (home.com)
vault write pki/root/generate/internal \
  common_name=home.com \
  ttl=8760h

# Configure the PKI secrets engine certificate issuing and certificate revocation list (CRL) endpoints
# to use the Vault service in the 'vault' namespace.
vault write pki/config/urls \
  issuing_certificates="http://vault.vault:8200/v1/pki/ca" \
  crl_distribution_points="http://vault.vault:8200/v1/pki/crl"

# Create role for local domain (home.com)
vault write pki/roles/home-dot-com \
  allowed_domains=home.com \
  allow_subdomains=true \
  max_ttl=72h \
  require_cn=false \
  allow_any_name=true

# Create policy
vault policy write pki - <<EOF
path "pki*"                        { capabilities = ["read", "list"] }
path "pki/roles/home-dot-com"   { capabilities = ["create", "update"] }
path "pki/sign/home-dot-com"    { capabilities = ["create", "update"] }
path "pki/issue/home-dot-com"   { capabilities = ["create"] }
EOF

# Configure kubernetes authentication method
vault auth enable kubernetes

# Configure the Kubernetes authentication method to use location of the Kubernetes API
k8sApiServer=$(kubectl get svc kubernetes -o jsonpath="{.spec.clusterIP}")
vault write auth/kubernetes/config kubernetes_host="https://${k8sApiServer}:443"

# Create a Kubernetes authentication role named issuer that binds the pki policy with a Kubernetes service account named vault-issuer-sa
# Account must be is cert-manager namespace to be accessible by the cluster issuer
vault write auth/kubernetes/role/issuer \
  bound_service_account_names=vault-issuer-sa \
  bound_service_account_namespaces=cert-manager \
  policies=pki \
  ttl=20m

# Create the service account in the cert-manager namespace
kubectl create serviceaccount vault-issuer-sa -n cert-manager
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-issuer-sa-token
  namespace: cert-manager
  annotations:
    kubernetes.io/service-account.name: vault-issuer-sa
type: kubernetes.io/service-account-token
EOF

# Create a certificate issuer linked to issuer service account
issuerServiceAccountSecret="$(kubectl get secrets -n cert-manager --output=go-template={{.metadata.name}} vault-issuer-sa-token)"
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    auth:
      kubernetes:
        mountPath: /v1/auth/kubernetes
        role: issuer
        secretRef:
          key: token
          name: $issuerServiceAccountSecret
    path: pki/sign/home-dot-com
    server: http://vault.vault:8200
EOF

# Kill port-forward process
kill -9 $portForwardPid
