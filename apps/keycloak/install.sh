#!/usr/bin/env bash

# Install Operator Lifecycle Manager
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.22.0/install.sh | bash -s v0.22.0

# Install Keycloak Operator
kubectl create -f ./keycloak-operator.yaml

# Install Keycloak instance
kubectl create -f ./keycloak.yaml

# Install ingress
kubectl create -f ./keycloak-ingress.yaml