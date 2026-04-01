#!/usr/bin/env bash

set -euo pipefail

### Cau hinh co ban (sua lai cho phu hop moi truong Linux cua ban)
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-phuceks}"
# Mode: stateful-alb | stateful-istio | knative-istio
MODE="${MODE:-stateful-alb}"

RUN_TERRAFORM="${RUN_TERRAFORM:-false}"   # true/false
RUN_VAULT="${RUN_VAULT:-false}"           # true/false

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "❌ Khong tim thay lenh: $name" >&2
    exit 1
  fi
}

apply_yaml_recursive() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "⚠️ Thu muc khong ton tai: $dir"
    return
  fi
  find "$dir" -type f -name '*.yaml' -print0 | while IFS= read -r -d '' f; do
    echo "kubectl apply -f \"$f\""
    kubectl apply -f "$f"
  done
}

apply_yaml() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "⚠️ File khong ton tai: $file"
    return
  fi
  echo "kubectl apply -f \"$file\""
  kubectl apply -f "$file"
}

echo "== Deploy all (Linux) - mode: $MODE =="

require_cmd aws
require_cmd kubectl

if [[ "$RUN_TERRAFORM" == "true" ]]; then
  require_cmd terraform
fi

if [[ "$MODE" == "stateful-alb" || "$MODE" == "stateful-istio" || "$MODE" == "knative-istio" ]]; then
  require_cmd helm
fi

if [[ "$MODE" == "stateful-istio" || "$MODE" == "knative-istio" ]]; then
  require_cmd istioctl
fi

echo "== Cap nhat kubeconfig =="
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl cluster-info

if [[ "$RUN_TERRAFORM" == "true" ]]; then
  echo "== Terraform apply =="
  pushd "$ROOT_DIR/terraform" >/dev/null
  terraform init
  terraform apply
  popd >/dev/null
fi

echo "== Deploy core services: MySQL + Redis + Kafka (Linux) =="
apply_yaml "$ROOT_DIR/mysql/mysql.yaml"
apply_yaml "$ROOT_DIR/redis/redis.yaml"

echo "== Deploy Kafka (Helm chart) =="
pushd "$ROOT_DIR/kafka" >/dev/null
bash deploy_kafka.sh
popd >/dev/null

if [[ "$RUN_VAULT" == "true" ]]; then
  require_cmd jq
  echo "== Deploy Vault =="
  pushd "$ROOT_DIR/vault" >/dev/null
  bash deploy_vault.sh
  popd >/dev/null
fi

echo "== Deploy application layer - mode: $MODE =="

case "$MODE" in
  stateful-alb)
    apply_yaml_recursive "$ROOT_DIR/stateful/services"
    apply_yaml "$ROOT_DIR/stateful/alb/aws-load-balancer-controller/crds/crds.yaml"
    helm upgrade --install aws-load-balancer-controller \
      -n kube-system --create-namespace \
      "$ROOT_DIR/stateful/alb/aws-load-balancer-controller" \
      -f "$ROOT_DIR/stateful/alb/aws-load-balancer-controller/values.yaml"
    apply_yaml "$ROOT_DIR/stateful/alb/ing.yaml"
    echo "DNS: trỏ test.onefirefly.click / api.onefirefly.click ve ADDRESS cua kubectl get ingress."
    ;;

  stateful-istio)
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update
    istioctl x precheck
    helm upgrade --install istio-base istio/base \
      --namespace istio-system --create-namespace \
      --version 1.18.2 --set profile=demo
    helm upgrade --install istiod istio/istiod \
      --namespace istio-system \
      --version 1.18.2 --wait --set profile=demo
    helm upgrade --install istio-ingress istio/gateway \
      --namespace istio-ingress --create-namespace \
      --version 1.18.2

    apply_yaml_recursive "$ROOT_DIR/stateful/services"
    apply_yaml "$ROOT_DIR/stateful/istio/gateway.yaml"
    apply_yaml "$ROOT_DIR/stateful/istio/virtual-services.yaml"
    echo "DNS: trỏ test.onefirefly.click / api.onefirefly.click ve EXTERNAL-IP cua svc istio-ingress."
    ;;

  knative-istio)
    istioctl install -y
    kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml
    helm repo add knative-operator https://knative.github.io/operator
    helm upgrade --install knative-operator knative-operator/knative-operator \
      --namespace knative-operator --create-namespace
    apply_yaml "$ROOT_DIR/knative/namespace.yaml"
    apply_yaml_recursive "$ROOT_DIR/knative/services"
    echo "DNS: trỏ domain trong knative/services/domain-mapping.yaml ve Istio ingress gateway."
    ;;

  *)
    echo "❌ MODE khong hop le: $MODE (stateful-alb | stateful-istio | knative-istio)" >&2
    exit 1
    ;;
esac

echo "== Done (Linux deploy_all.sh) =="

