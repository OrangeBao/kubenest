#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

CURRENT="$(dirname "${BASH_SOURCE[0]}")"
ROOT=$(dirname "${BASH_SOURCE[0]}")/..
# true: when cluster is exist, reuse exist one!
REUSE=${REUSE:-false}
# Set to false in a restricted internet environment.
USE_LOCAL_ARTIFACTS=${USE_LOCAL_ARTIFACTS:-true}
VERSION=${VERSION:-latest}

CN_ZONE=${CN_ZONE:-false}
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"

# default cert and key for node server https
#CERT=$(util::get_base64_kubeconfig ${ROOT}/pkg/cert/crt.pem)
#KEY=$(util::get_base64_kubeconfig ${ROOT}/pkg/cert/crt.pem)

if [ $REUSE == true ]; then
  echo "!!!!!!!!!!!Warning: Setting REUSE to true will not delete existing clusters.!!!!!!!!!!!"
fi

source "${ROOT}/hack/util.sh"

# pull e2e test image
function prepare_test_image() {
  if [ "${CN_ZONE}" == false ]; then
    docker pull bitpoke/mysql-operator-orchestrator:v0.6.3
    docker pull bitpoke/mysql-operator:v0.6.3
    docker pull bitpoke/mysql-operator-sidecar-5.7:v0.6.3
    docker pull nginx
    docker pull percona:5.7
    docker pull prom/mysqld-exporter:v0.13.0
  else
    #    todo add bitpoke to m.daocloud.io's Whitelist
    docker pull bitpoke/mysql-operator-orchestrator:v0.6.3
    docker pull bitpoke/mysql-operator:v0.6.3
    docker pull bitpoke/mysql-operator-sidecar-5.7:v0.6.3
    docker pull docker.m.daocloud.io/nginx
    docker pull docker.m.daocloud.io/percona:5.7
    docker pull docker.m.daocloud.io/prom/mysqld-exporter:v0.13.0

    docker tag docker.m.daocloud.io/bitpoke/mysql-operator-orchestrator:v0.6.3 bitpoke/mysql-operator-orchestrator:v0.6.3
    docker tag docker.m.daocloud.io/bitpoke/mysql-operator:v0.6.3 bitpoke/mysql-operator:v0.6.3
    docker tag docker.m.daocloud.io/bitpoke/mysql-operator-sidecar-5.7:v0.6.3 bitpoke/mysql-operator-sidecar-5.7:v0.6.3
    docker tag docker.m.daocloud.io/nginx nginx
    docker tag docker.m.daocloud.io/percona:5.7 percona:5.7
    docker tag docker.m.daocloud.io/prom/mysqld-exporter:v0.13.0 prom/mysqld-exporter:v0.13.0
  fi
}

## create a docker registry for kind
#function create_docker_registry() {
#  if [ "${USE_LOCAL_ARTIFACTS}" == true ]; then
#    docker network create kind
#    if [ "${CN_ZONE}" == false ]; then
#      docker run -d --network host --restart=always --name registry registry:2
#    else
#      docker run -d --network host --restart=always --name registry m.daocloud.io/docker.io/registry:2
#    fi
#    docker network create kind
#    docker network connect kind registry
#  else
#    echo "Do nothing because USE_LOCAL_ARTIFACTS is false"
#  fi
#}

# prepare e2e cluster
function prepare_e2e_cluster() {
  local -r clustername=$1
  CLUSTER_DIR="${ROOT}/environments/${clustername}"

  # load image for kind
  kind load docker-image bitpoke/mysql-operator-orchestrator:v0.6.3 --name "${clustername}"
  kind load docker-image bitpoke/mysql-operator:v0.6.3 --name "${clustername}"
  kind load docker-image bitpoke/mysql-operator-sidecar-5.7:v0.6.3 --name "${clustername}"
  kind load docker-image nginx --name "${clustername}"
  kind load docker-image percona:5.7 --name "${clustername}"
  kind load docker-image prom/mysqld-exporter:v0.13.0 --name "${clustername}"

  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig apply -f "$ROOT"/deploy/crds

  # deploy kosmos-scheduler for e2e test case of mysql-operator
  sed -e "s|__VERSION__|$VERSION|g" -e "w ${ROOT}/environments/kosmos-scheduler.yml" "$ROOT"/deploy/scheduler/deployment.yaml
  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig apply -f "${ROOT}/environments/kosmos-scheduler.yml"
  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig apply -f "$ROOT"/deploy/scheduler/rbac.yaml

  util::wait_for_condition "kosmos scheduler are ready" \
    "kubectl --kubeconfig $CLUSTER_DIR/kubeconfig -n kosmos-system get deploy kosmos-scheduler -o jsonpath='{.status.replicas}{\" \"}{.status.readyReplicas}{\"\n\"}' | awk '{if (\$1 == \$2 && \$1 > 0) exit 0; else exit 1}'" \
    300
  echo "cluster $clustername deploy kosmos-scheduler success"

  docker exec ${clustername}-control-plane /bin/sh -c "mv /etc/kubernetes/manifests/kube-scheduler.yaml /etc/kubernetes"

  # add the args for e2e test case of mysql-operator
  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig -n kosmos-system patch deployment clustertree-cluster-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--auto-mcs-prefix=kosmos-e2e"}]'

  util::wait_for_condition "kosmos ${clustername} clustertree are ready" \
    "kubectl --kubeconfig $CLUSTER_DIR/kubeconfig -n kosmos-system get deploy clustertree-cluster-manager -o jsonpath='{.status.replicas}{\" \"}{.status.readyReplicas}{\"\n\"}' | awk '{if (\$1 == \$2 && \$1 > 0) exit 0; else exit 1}'" \
    300
}

function prepare_docker_image() {
  # 定义 Calico 镜像的基础名称和版本
  local calico_images=(
    "calico/apiserver"
    "calico/cni"
    "calico/csi"
    "calico/kube-controllers"
    "calico/node-driver-registrar"
    "calico/node"
    "calico/pod2daemon-flexvol"
    "calico/typha"
  )
  local operator_image="tigera/operator"
  local version="v3.25.0"
  local operator_version="v1.29.0"

  if [ "${CN_ZONE}" == false ]; then
    # 使用 Calico 的官方镜像源
    local calico_prefix=""
    local operator_prefix="quay.io"
  else
    # 使用 DaoCloud 镜像源
    calico_prefix="docker.m.daocloud.io/"
    operator_prefix="quay.m.daocloud.io"
  fi

  # 拉取和标记 Calico 镜像
  for image in "${calico_images[@]}"; do
    docker pull "${calico_prefix}${image}:${version}"
    docker tag "${calico_prefix}${image}:${version}" "${image}:${version}"
  done

  # 拉取和标记 Operator 镜像
  docker pull "${operator_prefix}/${operator_image}:${operator_version}"
  docker tag "${operator_prefix}/${operator_image}:${operator_version}" "${operator_image}:${operator_version}"
}

#clustername podcidr servicecidr
function create_cluster() {
  local -r KIND_IMAGE=$1
  local -r hostIpAddress=$2
  local -r clustername=$3
  local -r podcidr=$4
  local -r servicecidr=$5
  local -r isDual=${6:-false}
  local KIND_CONFIG_NAME="kindconfig"

  CLUSTER_DIR="${ROOT}/environments/${clustername}"
  mkdir -p "${CLUSTER_DIR}"

  echo "$CLUSTER_DIR"

  ipFamily=ipv4
  if [ "$isDual" == true ]; then
    ipFamily=dual
    pod_convert=$(printf %x $(echo $podcidr | awk -F "." '{print $2" "$3}'))
    svc_convert=$(printf %x $(echo $servicecidr | awk -F "." '{print $2" "$3}'))
    podcidr_ipv6="fd11:1111:1111:"$pod_convert"::/64"
    servicecidr_ipv6="fd11:1111:1112:"$svc_convert"::/108"
    podcidr_all=${podcidr_ipv6}","${podcidr}
    servicecidr_all=${servicecidr_ipv6}","${servicecidr}
    sed -e "s|__POD_CIDR__|$podcidr|g" -e "s|__POD_CIDR_IPV6__|$podcidr_ipv6|g" -e "s|#DUAL||g" -e "w ${CLUSTER_DIR}/calicoconfig" "${CURRENT}/clustertemplete/calicoconfig"
    sed -e "s|__POD_CIDR__|$podcidr_all|g" -e "s|__SERVICE_CIDR__|$servicecidr_all|g" -e "s|__IP_FAMILY__|$ipFamily|g" -e "w ${CLUSTER_DIR}/${KIND_CONFIG_NAME}" "${CURRENT}/clustertemplete/${KIND_CONFIG_NAME}"
  else
    sed -e "s|__POD_CIDR__|$podcidr|g" -e "s|__SERVICE_CIDR__|$servicecidr|g" -e "s|__IP_FAMILY__|$ipFamily|g" -e "w ${CLUSTER_DIR}/${KIND_CONFIG_NAME}" "${CURRENT}/clustertemplete/${KIND_CONFIG_NAME}"
    sed -e "s|__POD_CIDR__|$podcidr|g" -e "s|__SERVICE_CIDR__|$servicecidr|g" -e "w ${CLUSTER_DIR}/calicoconfig" "${CURRENT}/clustertemplete/calicoconfig"
  fi

  sed -i'' -e "s/__HOST_IPADDRESS__/${hostIpAddress}/g" ${CLUSTER_DIR}/${KIND_CONFIG_NAME}
  if [[ "$(kind get clusters | grep -c "${clustername}")" -eq 1 && "${REUSE}" = true ]]; then
    echo "cluster ${clustername} exist reuse it"
  else
    kind delete clusters $clustername || true
    echo "create cluster ${clustername} with kind image ${KIND_IMAGE}"
    kind create cluster --name "${clustername}" --config "${CLUSTER_DIR}/${KIND_CONFIG_NAME}" --image "${KIND_IMAGE}"
  fi

  # load docker image to kind cluster
  kind load docker-image calico/apiserver:v3.25.0 --name $clustername
  kind load docker-image calico/cni:v3.25.0 --name $clustername
  kind load docker-image calico/csi:v3.25.0 --name $clustername
  kind load docker-image calico/kube-controllers:v3.25.0 --name $clustername
  kind load docker-image calico/node-driver-registrar:v3.25.0 --name $clustername
  kind load docker-image calico/node:v3.25.0 --name $clustername
  kind load docker-image calico/pod2daemon-flexvol:v3.25.0 --name $clustername
  kind load docker-image calico/typha:v3.25.0 --name $clustername
  kind load docker-image quay.io/tigera/operator:v1.29.0 --name $clustername

  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig taint nodes --all node-role.kubernetes.io/control-plane- || true

  # prepare external kubeconfig
  kind get kubeconfig --name "${clustername}" >"${CLUSTER_DIR}/kubeconfig"
  dockerip=$(docker inspect "${clustername}-control-plane" --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}")
  echo "get docker ip from pod $dockerip"
  docker exec ${clustername}-control-plane /bin/sh -c "cat /etc/kubernetes/admin.conf" | sed -e "s|${clustername}-control-plane|$dockerip|g" -e "/certificate-authority-data:/d" -e "5s/^/    insecure-skip-tls-verify: true\n/" -e "w ${CLUSTER_DIR}/kubeconfig-nodeIp"

  # 本地测试环境使用本地制品库，github ci 环境直接使用公网的镜像和yaml
  if [ "${USE_LOCAL_ARTIFACTS}" == true ]; then
    kubectl --kubeconfig $CLUSTER_DIR/kubeconfig create -f "${CURRENT}/artifacts/calicooperator/tigera-operator.yaml" || $("${REUSE}" -eq "true")
  else
    kubectl --kubeconfig $CLUSTER_DIR/kubeconfig create -f "https://raw.githubusercontent.com/projectcalico/calico/master/manifests/tigera-operator.yaml" || $("${REUSE}" -eq "true")
  fi

  kind export kubeconfig --name "$clustername"
  util::wait_for_crd installations.operator.tigera.io
  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig apply -f "${CLUSTER_DIR}"/calicoconfig
  echo "create cluster ${clustername} success"
  echo "wait all node ready"
  # N = nodeNum + 1
  N=$(kubectl --kubeconfig $CLUSTER_DIR/kubeconfig get nodes --no-headers | wc -l)
  util::wait_for_condition "all nodes are ready" \
    "kubectl --kubeconfig $CLUSTER_DIR/kubeconfig get nodes | awk 'NR>1 {if (\$2 != \"Ready\") exit 1; }' && [ \$(kubectl --kubeconfig $CLUSTER_DIR/kubeconfig get nodes --no-headers | wc -l) -eq ${N} ]" \
    300
  echo "all node ready"
}

function load_kubenetst_cluster_images() {
  local -r clustername=$1

  #  kind load docker-image -n "$clustername" ghcr.io/kosmos-io/virtual-cluster-operator:"${VERSION}"
  kind load docker-image -n "$clustername" ghcr.io/kosmos-io/node-agent:"${VERSION}"
}

function create_node_agent_daemonset() {
  # insure htpasswd
  util::cmd_must_exist openssl
  # generate username and password
  username=$(openssl rand -hex 5)
  password=$(openssl rand -base64 12)
  echo "node-agent生成的用户名: $username"
  echo "node-agent生成的密码: $password"
  # Base64 encode the username and password
  encoded_username=$(echo -n "$username" | base64)
  encoded_password=$(echo -n "$password" | base64)

  sed -e "s|^  username:.*|  username: ${encoded_username}|g" \
    -e "s|^  password:.*|  password: ${encoded_password}|g" \
    -e "w ${ROOT}/environments/node-agent.yaml" "$ROOT"/deploy/node-agent.yaml

  local -r clustername=$1
  CLUSTER_DIR="${ROOT}/environments/${clustername}"
  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig apply -f "${ROOT}/environments/node-agent.yaml"
}

function delete_cluster() {
  local -r clusterName=$1
  local -r clusterDir=$2

  kind delete clusters "${clusterName}"
  rm -rf "${clusterDir}"
  echo "cluster $clusterName delete success"
}
