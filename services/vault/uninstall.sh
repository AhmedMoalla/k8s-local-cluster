#!/usr/bin/env bash

helm uninstall vault -n vault
kubectl delete pvc -n vault data-vault-0
kubectl delete serviceaccount vault-issuer-sa -n cert-manager
kubectl delete clusterissuer vault-issuer
kubectl delete namespace vault
