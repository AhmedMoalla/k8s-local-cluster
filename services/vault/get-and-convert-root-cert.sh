#!/usr/bin/env bash

# Port forward internal vault service in background and suppress output
kubectl port-forward -n vault svc/vault 8200:8200 &
# Get PID of port-forward process
portForwardPid=$!
echo "Port forward PID: $portForwardPid"
# Wait for port-forward to be ready
sleep 5

# Get root cert
curl http://127.0.0.1:8200/v1/pki/ca/pem >home-dot-com.pem
# Convert a cert from .pem to .crt to be used in the Windows Certificate Store
openssl x509 -outform der -in home-dot-com.pem -out home-dot-com.crt
echo "Run 'sudo trust anchor --store home-dot-com.crt' to add certificate to trusted CA store"

# Kill port-forward process
kill -9 $portForwardPid
