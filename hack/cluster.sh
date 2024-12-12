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
REGISTRY=${REGISTRY:-192.168.200.1:5000}

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

function create_local_registry() {
  container_name="kubenest-registry"
  container_id=$(docker ps -q -f name=$container_name)

  if [ -z "$container_id" ]; then
    echo "$container_name 本地不存在"
    if [ "${CN_ZONE}" == false ]; then
      local registry_image="registry:2.7.1"
    else
      registry_image="dockem.daocloud.io/library/registry:2.7.1"
    fi
    # 创建虚拟网卡
    ip link add veth-host type veth peer name veth-docker
    ip addr add 192.168.200.1/24 dev veth-host
    ip link set veth-host up

    # 创建镜像仓库
    docker run --network host --restart=always -d --name kubenest-registry "${registry_image}"
    # Docker 配置文件路径
    docker_config="/etc/docker/daemon.json"

    # 检查并创建 Docker 配置文件
    if [ ! -f "$docker_config" ]; then
      echo '{}' >"$docker_config"
    fi

    # 备份原始文件
    cp "$docker_config" "${docker_config}.bak"

    # 更新 insecure-registries 配置
    if jq -e '. | has("insecure-registries")' "$docker_config" >/dev/null; then
      # 如果 insecure-registries 存在，添加新的 registry
      jq ".\"insecure-registries\" += [\"$REGISTRY\"]" "$docker_config" >"${docker_config}.tmp"
    else
      # 如果 insecure-registries 不存在，创建配置
      jq ". + {\"insecure-registries\": [\"$REGISTRY\"]}" "$docker_config" >"${docker_config}.tmp"
    fi

    # 替换原始配置文件
    mv "${docker_config}.tmp" "$docker_config"

    # 重启 Docker 服务以应用更改
    systemctl restart docker

    echo "已将 ${REGISTRY} 添加到 Docker 的 insecure-registries 配置中。"
  else
    echo "kubenest-registry 已经在本地存在"
  fi
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
  local calico_version="v3.25.0"
  local operator_version="v1.29.0"

  if [ "${CN_ZONE}" == false ]; then
    # 使用 Calico 的官方镜像源
    local docker_prefix=""
    local operator_prefix="quay.io"
  else
    # 使用 DaoCloud 镜像源
    docker_prefix="docker.m.daocloud.io/"
    operator_prefix="quay.m.daocloud.io"
  fi

  # 拉取和标记 Calico 镜像
  for image in "${calico_images[@]}"; do
    docker pull "${docker_prefix}${image}:${calico_version}"
  done

  # 拉取和标记 Operator 镜像
  docker pull "${operator_prefix}/${operator_image}:${operator_version}"

  # 镜像tag及推送
  for image in "${calico_images[@]}"; do
    docker tag "${docker_prefix}${image}:${calico_version}" "${REGISTRY}/${image}:${calico_version}"
    docker push "${REGISTRY}/${image}:${calico_version}"
  done

  docker tag "${operator_prefix}/${operator_image}:${operator_version}" "${REGISTRY}"/${operator_image}:${operator_version}
  docker push "${REGISTRY}"/${operator_image}:${operator_version}
}

function prepare_kubenest_image() {
  docker tag ghcr.io/kosmos-io/node-agent:"${VERSION}" "${REGISTRY}"/kosmos-io/node-agent:"${VERSION}"
  docker push "${REGISTRY}"/kosmos-io/node-agent:"${VERSION}"
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
  REGISTRY_URL="http://${REGISTRY}"
  # use "#" for fix http url error
  echo "REGISTRY is $REGISTRY"
  echo "REGISTRY_URL is $REGISTRY_URL"
  sed -i'' -e "s/__HOST_IPADDRESS__/${hostIpAddress}/g" -e "s#__REGISTRY__#${REGISTRY_URL}#g" -e "s#__REGISTRY_DOMAIN__#${REGISTRY}#g" "${CLUSTER_DIR}"/${KIND_CONFIG_NAME}
  if [[ "$(kind get clusters | grep -c "${clustername}")" -eq 1 && "${REUSE}" = true ]]; then
    echo "cluster ${clustername} exist reuse it"
  else
    kind delete clusters $clustername || true
    echo "create cluster ${clustername} with kind image ${KIND_IMAGE}"
    kind create cluster --name "${clustername}" --config "${CLUSTER_DIR}/${KIND_CONFIG_NAME}" --image "${KIND_IMAGE}"
  fi

  kubectl --kubeconfig $CLUSTER_DIR/kubeconfig taint nodes --all node-role.kubernetes.io/control-plane- || true

  # prepare external kubeconfig
  kind get kubeconfig --name "${clustername}" >"${CLUSTER_DIR}/kubeconfig"
  dockerip=$(docker inspect "${clustername}-control-plane" --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}")
  echo "get docker ip from pod $dockerip"
  docker exec "${clustername}"-control-plane /bin/sh -c "cat /etc/kubernetes/admin.conf" | sed -e "s|${clustername}-control-plane|$dockerip|g" -e "/certificate-authority-data:/d" -e "5s/^/    insecure-skip-tls-verify: true\n/" -e "w ${CLUSTER_DIR}/kubeconfig-nodeIp"

  # 本地测试环境使用本地制品库，github ci 环境直接使用公网的镜像和yaml
  if [ "${USE_LOCAL_ARTIFACTS}" == true ]; then
    sed -e "s|{{ .REGISTRY }}|${REGISTRY}|g" \
      -e "w ${ROOT}/environments/tigera-operator.yaml" "$ROOT"/hack/artifacts/calicooperator/tigera-operator.yaml
    sed -e "s|{{ .REGISTRY }}|${REGISTRY}|g" \
      -e "w ${ROOT}/environments/installation.yaml" "$ROOT"/hack/artifacts/calicooperator/installation.yaml
    kubectl --kubeconfig "$CLUSTER_DIR"/kubeconfig create -f "${ROOT}"/environments/tigera-operator.yaml || $("${REUSE}" -eq "true")
    kubectl --kubeconfig "$CLUSTER_DIR"/kubeconfig create -f "${ROOT}"/environments/installation.yaml || $("${REUSE}" -eq "true")
  else
    kubectl --kubeconfig "$CLUSTER_DIR"/kubeconfig create -f "https://raw.githubusercontent.com/projectcalico/calico/master/manifests/tigera-operator.yaml" || $("${REUSE}" -eq "true")
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

function create_node_agent_daemonset() {
  local -r clustername=$1
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

  sed -e "s|{{ .USERNAME }}|${encoded_username}|g" \
    -e "s|{{ .PASSWORD }}|${encoded_password}|g" \
    -e "s|{{ .REGISTRY }}|${REGISTRY}|g" \
    -e "w ${ROOT}/environments/node-agent.yaml" "$ROOT"/deploy/node-agent.yaml

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
