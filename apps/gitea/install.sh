#!/usr/bin/env bash

helm repo add gitea-charts https://dl.gitea.io/charts/
helm repo update
kubectl apply -f ./gitea-admin-user-secret.yaml
helm install gitea gitea-charts/gitea -f ./gitea-chart-values.yaml
