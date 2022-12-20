#!/usr/bin/env bash

# Port forward internal vault service in background and suppress output
kubectl port-forward -n vault svc/vault 8200:8200 &
# Get PID of port-forward process
portForwardPid=$!
echo "Port forward PID: $portForwardPid"
# Wait for port-forward to be ready
sleep 5

export VAULT_ADDR="http://localhost:8200"

vault operator unseal "$(jq -r ".unseal_keys_b64[]" init-keys.json)"

kill -9 $portForwardPid