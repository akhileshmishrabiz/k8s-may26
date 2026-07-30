#!/bin/bash
#
# Install Linkerd service mesh + ecommerce NetworkPolicies on the existing
# ecommerce-vault Kind cluster (no cluster recreation).
#
# Usage:
#   ./deploy.sh                 # Linkerd control plane + viz + policies + mesh policies
#   ./deploy.sh --mesh-only     # Linkerd only (skip NetworkPolicies)
#   ./deploy.sh --policies-only # NetworkPolicies only (skip Linkerd)
#   ./deploy.sh --help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="ecommerce-vault"
APP_NAMESPACE="ecommerce"
MONITORING_NAMESPACE="monitoring"
LINKERD_NAMESPACE="linkerd"
LINKERD_VIZ_NAMESPACE="linkerd-viz"
LINKERD_VERSION="stable-2.14.10"
PROXY_INIT_VERSION="v2.2.3"
CERT_DIR="${SCRIPT_DIR}/.certs"

INSTALL_MESH=true
INSTALL_POLICIES=true

for arg in "$@"; do
    case "$arg" in
        --mesh-only)
            INSTALL_POLICIES=false
            ;;
        --policies-only)
            INSTALL_MESH=false
            ;;
        --help|-h)
            echo "Usage: $0 [--mesh-only|--policies-only]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--mesh-only|--policies-only]"
            exit 1
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_info() { echo -e "${YELLOW}INFO: $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ ERROR: $1${NC}"; exit 1; }

load_image_into_kind() {
    local img="$1"
    if docker exec "${CLUSTER_NAME}-control-plane" ctr -n k8s.io images ls -q | grep -q "${img##*/}" 2>/dev/null; then
        print_info "Skipping ${img} (already in Kind)"
        return
    fi
    print_info "Loading ${img} into Kind..."
    docker pull "${img}"
    docker save "${img}" | docker exec -i "${CLUSTER_NAME}-control-plane" \
        ctr -n k8s.io images import -
    print_success "Loaded ${img}"
}

generate_linkerd_certs() {
    mkdir -p "${CERT_DIR}"

    if [ -f "${CERT_DIR}/ca.crt" ] && [ -f "${CERT_DIR}/issuer.crt" ] && [ -f "${CERT_DIR}/issuer.key" ]; then
        # Re-validate issuer is an intermediate CA (Linkerd requirement)
        if openssl x509 -in "${CERT_DIR}/issuer.crt" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
            print_info "Reusing existing Linkerd identity certs in ${CERT_DIR}"
            return
        fi
        print_info "Existing issuer cert invalid — regenerating..."
        rm -f "${CERT_DIR}"/*
    fi

    print_info "Generating Linkerd trust anchor and issuer certificates (openssl)..."

    cat > "${CERT_DIR}/openssl.cnf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = root.linkerd.cluster.local

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash

[v3_intermediate_ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "${CERT_DIR}/ca.key" -out "${CERT_DIR}/ca.crt" \
        -config "${CERT_DIR}/openssl.cnf" -extensions v3_ca

    openssl req -newkey rsa:4096 -nodes \
        -keyout "${CERT_DIR}/issuer.key" -out "${CERT_DIR}/issuer.csr" \
        -subj "/CN=identity.linkerd.cluster.local"

    openssl x509 -req -in "${CERT_DIR}/issuer.csr" \
        -CA "${CERT_DIR}/ca.crt" -CAkey "${CERT_DIR}/ca.key" -CAcreateserial \
        -out "${CERT_DIR}/issuer.crt" -days 365 -sha256 \
        -extfile "${CERT_DIR}/openssl.cnf" -extensions v3_intermediate_ca

    print_success "Linkerd certificates generated"
}

install_linkerd_mesh() {
    print_step "1" "Installing Linkerd Control Plane"

    helm repo add linkerd https://helm.linkerd.io/stable 2>/dev/null || true
    helm repo update linkerd

    LINKERD_IMAGES=(
        "cr.l5d.io/linkerd/controller:${LINKERD_VERSION}"
        "cr.l5d.io/linkerd/proxy:${LINKERD_VERSION}"
        "cr.l5d.io/linkerd/proxy-init:${PROXY_INIT_VERSION}"
        "cr.l5d.io/linkerd/policy-controller:${LINKERD_VERSION}"
        "cr.l5d.io/linkerd/metrics-api:${LINKERD_VERSION}"
        "cr.l5d.io/linkerd/tap:${LINKERD_VERSION}"
        "cr.l5d.io/linkerd/web:${LINKERD_VERSION}"
    )

    for img in "${LINKERD_IMAGES[@]}"; do
        load_image_into_kind "${img}"
    done

    generate_linkerd_certs

    print_info "Validating Linkerd Helm charts (helm template)..."
    helm template test-crds linkerd/linkerd-crds >/dev/null
    helm template test-cp linkerd/linkerd-control-plane -f "${SCRIPT_DIR}/values.yaml" \
        --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
        --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
        --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" >/dev/null
    helm template test-viz linkerd/linkerd-viz -f "${SCRIPT_DIR}/values-viz.yaml" >/dev/null
    print_success "Helm charts valid"

    if helm status linkerd-crds -n "${LINKERD_NAMESPACE}" >/dev/null 2>&1; then
        print_info "Upgrading linkerd-crds..."
        helm upgrade linkerd-crds linkerd/linkerd-crds -n "${LINKERD_NAMESPACE}" --timeout 5m
    else
        print_info "Installing linkerd-crds..."
        helm install linkerd-crds linkerd/linkerd-crds -n "${LINKERD_NAMESPACE}" --create-namespace --timeout 5m
    fi

    kubectl wait --for=condition=Established crd/serverauthorizations.policy.linkerd.io --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=Established crd/servers.policy.linkerd.io --timeout=120s 2>/dev/null || true

    if helm status linkerd-control-plane -n "${LINKERD_NAMESPACE}" >/dev/null 2>&1; then
        print_info "Upgrading linkerd-control-plane..."
        helm upgrade linkerd-control-plane linkerd/linkerd-control-plane \
            -n "${LINKERD_NAMESPACE}" \
            -f "${SCRIPT_DIR}/values.yaml" \
            --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
            --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
            --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" \
            --timeout 5m
    else
        print_info "Installing linkerd-control-plane..."
        helm install linkerd-control-plane linkerd/linkerd-control-plane \
            -n "${LINKERD_NAMESPACE}" \
            -f "${SCRIPT_DIR}/values.yaml" \
            --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
            --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
            --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" \
            --timeout 5m
    fi

    print_info "Waiting for Linkerd control plane..."
    kubectl wait --for=condition=available deployment/linkerd-destination \
        -n "${LINKERD_NAMESPACE}" --timeout=180s
    kubectl wait --for=condition=available deployment/linkerd-identity \
        -n "${LINKERD_NAMESPACE}" --timeout=180s
    kubectl wait --for=condition=available deployment/linkerd-proxy-injector \
        -n "${LINKERD_NAMESPACE}" --timeout=180s
    print_success "Linkerd control plane ready"

    print_step "2" "Installing Linkerd Viz"

    if helm status linkerd-viz -n "${LINKERD_VIZ_NAMESPACE}" >/dev/null 2>&1; then
        helm upgrade linkerd-viz linkerd/linkerd-viz \
            -n "${LINKERD_VIZ_NAMESPACE}" \
            -f "${SCRIPT_DIR}/values-viz.yaml" \
            --timeout 5m
    else
        helm install linkerd-viz linkerd/linkerd-viz \
            -n "${LINKERD_VIZ_NAMESPACE}" \
            --create-namespace \
            -f "${SCRIPT_DIR}/values-viz.yaml" \
            --timeout 5m
    fi

    kubectl wait --for=condition=available deployment/web \
        -n "${LINKERD_VIZ_NAMESPACE}" --timeout=180s
    print_success "Linkerd Viz ready"

    print_step "3" "Enabling Injection + Mesh Policies"

    kubectl apply -f "${SCRIPT_DIR}/mesh/namespace-annotation.yaml"
    kubectl apply -f "${SCRIPT_DIR}/mesh/server-authorization/meshed-auth.yaml"
    kubectl apply -f "${SCRIPT_DIR}/mesh/server-authorization/servers.yaml"

    print_info "Restarting ecommerce Deployments/StatefulSets to inject Linkerd proxies..."
    for kind in deployment statefulset; do
        for name in $(kubectl get "${kind}" -n "${APP_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            kubectl rollout restart "${kind}/${name}" -n "${APP_NAMESPACE}"
        done
    done

    print_info "Waiting for rollouts (meshed pods)..."
    kubectl rollout status deployment -n "${APP_NAMESPACE}" --timeout=600s 2>/dev/null || true
    kubectl rollout status statefulset -n "${APP_NAMESPACE}" --timeout=600s 2>/dev/null || true
    print_success "Ecommerce workloads restarted with Linkerd injection"
}

install_network_policies() {
    print_step "4" "Applying NetworkPolicies (ecommerce namespace)"

    if ! kubectl get namespace "${APP_NAMESPACE}" >/dev/null 2>&1; then
        print_error "Namespace '${APP_NAMESPACE}' not found — deploy the app stack first"
    fi

    kubectl apply -f "${SCRIPT_DIR}/network-policies/"
    print_success "NetworkPolicies applied"
}

# ============================================================
# STEP 0: Prerequisites
# ============================================================
print_step "0" "Checking Prerequisites"

for cmd in docker kubectl helm openssl; do
    command -v "$cmd" >/dev/null 2>&1 || print_error "$cmd is not installed"
    print_success "$cmd found"
done

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_error "Kind cluster '${CLUSTER_NAME}' not found. Run observibility/deploy.sh first."
fi

kubectl config use-context "kind-${CLUSTER_NAME}"
kubectl cluster-info >/dev/null 2>&1 || print_error "Cannot reach cluster '${CLUSTER_NAME}'"
print_success "Using cluster kind-${CLUSTER_NAME}"

if [ "${INSTALL_MESH}" = true ]; then
    install_linkerd_mesh
fi

if [ "${INSTALL_POLICIES}" = true ]; then
    install_network_policies
fi

# ============================================================
# Summary
# ============================================================
print_step "5" "Linkerd + NetworkPolicy Deployment Complete"

echo -e "${YELLOW}Linkerd pods:${NC}"
kubectl get pods -n "${LINKERD_NAMESPACE}" 2>/dev/null || true
kubectl get pods -n "${LINKERD_VIZ_NAMESPACE}" 2>/dev/null || true

echo -e "\n${YELLOW}NetworkPolicies in ${APP_NAMESPACE}:${NC}"
kubectl get networkpolicy -n "${APP_NAMESPACE}" 2>/dev/null || true

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  LINKERD + NETWORK POLICIES READY${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}What was enforced:${NC}"
echo "  • Linkerd mTLS between meshed pods in ${APP_NAMESPACE} (automatic for injected proxies)"
echo "  • Linkerd Server CRs for HTTP protocol detection on microservice ports"
echo "  • Optional strict AuthorizationPolicy: mesh/server-authorization/authorization-policies.strict.yaml"
echo "  • default-deny-all baseline + explicit allow rules for DNS, gateway, services"
echo "  • Redis/RabbitMQ/Postgres restricted to authorized callers"
echo "  • Prometheus scrape + OTel export from ${MONITORING_NAMESPACE}"
echo ""
echo -e "${YELLOW}Access:${NC}"
echo "  Linkerd Viz dashboard:"
echo "    kubectl -n ${LINKERD_VIZ_NAMESPACE} port-forward svc/web 8084:8084"
echo "    open http://localhost:8084"
echo ""
echo -e "${YELLOW}Grafana / Prometheus integration:${NC}"
echo "  Linkerd Viz metrics-api exposes golden metrics at:"
echo "    http://linkerd-viz-metrics-api.${LINKERD_VIZ_NAMESPACE}.svc.cluster.local:8085/metrics"
echo "  Add a Prometheus scrape job or import the Linkerd dashboard into Grafana."
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  ${SCRIPT_DIR}/deploy.sh --policies-only   # re-apply NetworkPolicies only"
echo "  ${SCRIPT_DIR}/deploy.sh --mesh-only       # Linkerd install/upgrade only"
if command -v linkerd >/dev/null 2>&1; then
    echo "  linkerd check"
    echo "  linkerd viz stat deploy -n ${APP_NAMESPACE}"
else
    echo "  (optional) install linkerd CLI for: linkerd check / linkerd viz stat"
fi
echo ""
echo -e "${YELLOW}Kind caveats:${NC}"
echo "  • Apply AFTER the app stack is running; policies are additive on existing cluster"
echo "  • NodePort ingress uses broad allow rules — Kind source IPs are not pod CIDRs"
echo "  • If pods fail after injection, check: kubectl describe pod -n ${APP_NAMESPACE} <name>"
echo "  • CNPG/RabbitMQ/Redis are meshed — if a datastore fails probes, annotate with"
echo "    config.linkerd.io/skip-inbound-ports or config.linkerd.io/skip-outbound-ports"
echo "  • Vault/ESO run outside ${APP_NAMESPACE}; app pods use synced K8s Secrets (no Vault egress needed)"
echo "  • Delete mesh: helm uninstall linkerd-viz -n ${LINKERD_VIZ_NAMESPACE}; helm uninstall linkerd-control-plane linkerd-crds -n ${LINKERD_NAMESPACE}"
echo "  • Delete policies: kubectl delete networkpolicy -l app.kubernetes.io/part-of=ecommerce-network-policy -n ${APP_NAMESPACE}"
echo ""
print_success "Done!"
