#!/bin/bash

echo "🚀 Deploying Kafka and Zookeeper on Kubernetes using Helm..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/kafka"
VALUES_FILE="${SCRIPT_DIR}/kafka-values.yaml"
RELEASE_NAME="kafka"
NAMESPACE="${NAMESPACE:-default}"

TMP_DOCKER_CONFIG=""

cleanup() {
    if [ -n "$TMP_DOCKER_CONFIG" ] && [ -d "$TMP_DOCKER_CONFIG" ]; then
        rm -rf "$TMP_DOCKER_CONFIG"
    fi
}
trap cleanup EXIT

# =============================================================================
# STEP 1: Check Prerequisites
# =============================================================================
echo "🔍 Checking prerequisites..."

if ! command -v helm >/dev/null 2>&1; then
    echo "❌ helm is not installed"
    echo "Please install helm: https://helm.sh/docs/intro/install/"
    exit 1
fi
echo "✅ helm is installed"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ kubectl is not configured or cluster is not accessible"
    exit 1
fi
echo "✅ kubectl is configured"

if [ ! -f "$VALUES_FILE" ]; then
    echo "❌ values file not found: $VALUES_FILE"
    exit 1
fi

if [ ! -d "$CHART_DIR" ]; then
    echo "❌ chart directory not found: $CHART_DIR"
    exit 1
fi

# =============================================================================
# STEP 2: Prepare Helm Chart
# =============================================================================
echo "📦 Updating Helm chart dependencies..."

# Use a clean docker config to avoid Windows credential helper issues with OCI charts
TMP_DOCKER_CONFIG=$(mktemp -d)
echo "{}" > "${TMP_DOCKER_CONFIG}/config.json"
export DOCKER_CONFIG="${TMP_DOCKER_CONFIG}"
export HELM_EXPERIMENTAL_OCI=1

if ! helm dependency update "$CHART_DIR"; then
    echo "❌ Failed to fetch chart dependencies"
    exit 1
fi

# =============================================================================
# STEP 3: Deploy Kafka with Helm
# =============================================================================
echo "📚 Deploying Kafka using Helm chart..."
if helm status "$RELEASE_NAME" --namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "   📝 Upgrading existing release in namespace $NAMESPACE..."
else
    echo "   📦 Installing new release in namespace $NAMESPACE..."
fi

if helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --create-namespace; then
    echo "   ✅ Kafka chart applied"
else
    echo "   ❌ Failed to deploy Kafka"
    exit 1
fi

# =============================================================================
# STEP 4: Wait for Pods to be Ready
# =============================================================================
echo "⏳ Waiting for Zookeeper to be ready..."
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zookeeper \
    --namespace "$NAMESPACE" --timeout=300s; then
    echo "   ✅ Zookeeper pods are ready"
else
    echo "   ⚠️  Zookeeper pods are not ready yet"
fi

echo "⏳ Waiting for Kafka to be ready..."
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka \
    --namespace "$NAMESPACE" --timeout=300s; then
    echo "   ✅ Kafka pods are ready"
else
    echo "   ⚠️  Kafka pods are not ready yet"
fi

# =============================================================================
# DEPLOYMENT COMPLETE - Display Information
# =============================================================================
echo ""
echo "🎉 Kafka deployment complete!"
echo ""
echo "📊 Service Status:"
echo "   helm status $RELEASE_NAME --namespace $NAMESPACE"
echo "   kubectl get pods -l app.kubernetes.io/name=kafka -n $NAMESPACE"
echo "   kubectl get pods -l app.kubernetes.io/name=zookeeper -n $NAMESPACE"
echo ""
echo "🌐 Access:"
echo "   Kafka bootstrap: kafka.$NAMESPACE.svc.cluster.local:9092"
echo "   Zookeeper: kafka-zookeeper.$NAMESPACE.svc.cluster.local:2181"
