#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x



function usage() {
    echo "Usage:"
    echo "    hack/local-up-kubenest.sh [HOST_IPADDRESS] [-h]"
    echo "Args:"
    echo "    HOST_IPADDRESS: (required) if you want to export clusters' API server port to specific IP address"
    echo "    h: print help information"
}

while getopts 'h' OPT; do
    case $OPT in
        h)
          usage
          exit 0
          ;;
        ?)
          usage
          exit 1
          ;;
    esac
done

KUBECONFIG_PATH=${KUBECONFIG_PATH:-"${HOME}/.kube"}
export KUBECONFIG=$KUBECONFIG_PATH/"config"

KIND_IMAGE=${KIND_IMAGE:-"m.daocloud.io/docker.io/kindest/node:v1.27.2"}
HOST_IPADDRESS=${1:-}
KUBE_NEST_CLUSTER_NAME="kubenest-cluster"
CLUSTER_POD_CIDR="10.233.64.0/18"
CLUSTER_SERVICE_CIDR="10.233.0.0/18"

REPO_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
VERSION=${VERSION:-"latest"}
source "$(dirname "${BASH_SOURCE[0]}")/install_kind_kubectl.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"

#step1. create host cluster and member clusters in parallel
# host IP address: script parameter ahead of macOS IP
if [[ -z "${HOST_IPADDRESS}" ]]; then
  util::get_macos_ipaddress # Adapt for macOS
  HOST_IPADDRESS=${MAC_NIC_IPADDRESS:-}
fi
make images GOOS="linux" VERSION="$VERSION" --directory="${REPO_ROOT}"

os=$(go env GOOS)
arch=$(go env GOARCH)
export PATH=$PATH:"${REPO_ROOT}"/_output/bin/"$os"/"$arch"

# prepare docker image and push to registry
prepare_docker_image

create_cluster "${KIND_IMAGE}" "${HOST_IPADDRESS}" "${KUBE_NEST_CLUSTER_NAME}" "${CLUSTER_POD_CIDR}" "${CLUSTER_SERVICE_CIDR}" false true

load_kubenetst_cluster_images "${KUBE_NEST_CLUSTER_NAME}"


