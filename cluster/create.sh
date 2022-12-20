#!/usr/bin/env bash
set -e

K3S_VERSION="v1.24.9-rc1+k3s1"

# Arguments
if [ -z "$CLUSTER_IMAGE_NAME" ]; then
  CLUSTER_IMAGE_NAME="22.04"
fi

if [ -z "$CLUSTER_MASTER_NAME" ]; then
  CLUSTER_MASTER_NAME="master"
fi

if [ -z "$CLUSTER_WORKER_NAME_SUFFIX" ]; then
  CLUSTER_WORKER_NAME_SUFFIX="node"
fi

if [ -z "$CLUSTER_NB_WORKERS" ]; then
  CLUSTER_NB_WORKERS=2
fi

if [ -z "$CLUSTER_MASTER_NB_CORES" ]; then
  CLUSTER_MASTER_NB_CORES="4"
fi

if [ -z "$CLUSTER_MASTER_MEMORY" ]; then
  CLUSTER_MASTER_MEMORY="4G"
fi

if [ -z "$CLUSTER_WORKER_NB_CORES" ]; then
  CLUSTER_WORKER_NB_CORES="2"
fi

if [ -z "$CLUSTER_WORKER_MEMORY" ]; then
  CLUSTER_WORKER_MEMORY="4G"
fi

if [ -z "$CLUSTER_DISK_SIZE" ]; then
  CLUSTER_DISK_SIZE="20G"
fi

function create_node {
  nbCores=$1
  ramSize=$2
  diskSize=$3
  nodeName=$4
  echo "Creating node: $nodeName with $nbCores cores and $ramSize RAM and $diskSize disk"
  multipass launch -c "$nbCores" -m "$ramSize" -d "$diskSize" -n "$nodeName" $CLUSTER_IMAGE_NAME
}

masterToken=""
function extract_master_token {
  # Extract token from master node to init worker node
  masterToken=$(multipass exec $CLUSTER_MASTER_NAME -- bash -c "sudo cat /var/lib/rancher/k3s/server/node-token")
  echo "Master Token: $masterToken"
}

function copy_k3s_config {
  nodeName=$1
  multipass transfer config.yaml "${nodeName}:/home/ubuntu"
  multipass exec "$nodeName" -- sudo mkdir -p /etc/rancher/k3s
  multipass exec "$nodeName" -- sudo mv /home/ubuntu/config.yaml /etc/rancher/k3s/config.yaml 
}

function install_k3s_on_master {
  echo "Installing k3s on master node: '$CLUSTER_MASTER_NAME'"
  # Install k3s in master node
  copy_k3s_config $CLUSTER_MASTER_NAME
  multipass exec $CLUSTER_MASTER_NAME -- bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -"
  extract_master_token
}

function install_k3s_on_node {
  workerName=$1
  echo "Installing k3s on node: '$workerName'"
  if [ -z "$masterToken" ]; then
    echo "Master token is empty, cannot install k3s on worker node: '$workerName'"
    exit 1
  fi
  # Start k3s agent on worker node
  multipass exec "$workerName" -- bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} K3S_URL=https://${masterIp}:6443 K3S_TOKEN=$masterToken sh -"
}

function format_worker_number {
  workerNumber=$1
  if [ "$workerNumber" -lt 10 ]; then
    workerNumber="0$workerNumber"
  fi
  echo "$workerNumber"
}

function generate_kube_config {
  multipass exec $CLUSTER_MASTER_NAME -- bash -c "sudo cat /etc/rancher/k3s/k3s.yaml" >k3s.yaml
  # Replace default with k3s
  sed -i 's/: default/: k3s/g' k3s.yaml
  # Replace localhost with master dns name
  sed -i "s/127.0.0.1/${masterIp}/g" k3s.yaml
  # Merge with local kubeconfig
  KUBECONFIG=~/.kube/config:./k3s.yaml kubectl config view --flatten >/tmp/k3s_config.yaml
  cp /tmp/k3s_config.yaml ~/.kube/config
  rm /tmp/k3s_config.yaml
  rm k3s.yaml
  echo "Generated kubeconfig file in ~/.kube/config"
}

# Create Node Mode
createNodeMode=$1
if [ -n "$createNodeMode" ] && [ "$createNodeMode" = "add-node" ]; then
  echo "Creating node"
  # list nodes and extract the ones that are not master
  lastWorkerName=$(kubectl get nodes -o name | grep -v master | sort | tail -n1 | cut -d'/' -f2)
  lastWorkerNumber=${lastWorkerName:4:2}
  nextWorkerNumber=$(format_worker_number $((lastWorkerNumber + 1)))
  workerName="${CLUSTER_WORKER_NAME_SUFFIX}$nextWorkerNumber"
  create_node $CLUSTER_WORKER_NB_CORES $CLUSTER_WORKER_MEMORY $CLUSTER_DISK_SIZE "$workerName"
  extract_master_token
  install_k3s_on_node "$workerName"
  exit 0
fi

create_node $CLUSTER_MASTER_NB_CORES $CLUSTER_MASTER_MEMORY $CLUSTER_DISK_SIZE "$CLUSTER_MASTER_NAME"
install_k3s_on_master
masterIp=$(multipass list --format csv | grep master | cut -d, -f3)
echo "Master IP address: $masterIp"

#loop over workers
for i in $(seq 1 $CLUSTER_NB_WORKERS); do
  workerName="${CLUSTER_WORKER_NAME_SUFFIX}$(format_worker_number "$i")"
  create_node $CLUSTER_WORKER_NB_CORES $CLUSTER_WORKER_MEMORY $CLUSTER_DISK_SIZE "$workerName"
  install_k3s_on_node "$workerName"
done

generate_kube_config

# Set current context and show nodes
kubectl config use-context k3s
