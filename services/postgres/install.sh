#!/usr/bin/env bash

cd "$(dirname "$0")" || exit 0

chartName=$(helm list -o json | jq '.[].name' | grep postgres-operator | grep -v null)
if [ -n "$chartName" ]; then
  echo "Postgres Operator already installed. Skip."
  exit 0
fi

# Install pgadmin, postgres-operator and postgres-operator-ui
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
helm repo add runix https://helm.runix.net

helm repo update

helm install postgres-operator postgres-operator-charts/postgres-operator
helm install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui
helm install pgadmin runix/pgadmin4 -f pgadmin-chart-values.yaml

# Create postgres cluster and ingresses
kubectl apply -f postgres-cluster.yaml
kubectl apply -f postgres-operator-ui-ingress.yaml

echo "Waiting for pods to be ready..."
kubectl wait --for condition=ready pod -l app.kubernetes.io/name=postgres-operator
kubectl wait --for condition=ready pod -l app.kubernetes.io/name=postgres-operator-ui
kubectl wait --for condition=ready pod -l app.kubernetes.io/name=pgadmin4
kubectl wait --for condition=ready pod acid-postgres-0

echo "Postgres operator installed."