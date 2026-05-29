#!/usr/bin/env bash
# tests/01_network_policy.sh — celowo BEZ set -e (SIGKILL od NV nie killuje modułu)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="Network Policy"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"

# Podpowłoka zapewnia że SIGKILL od NeuVector nie zabija całego modułu
safe_run() {
  local pod_name="$1"; shift
  ( kubectl run "${pod_name}" \
      --namespace="${NS}" \
      --image=curlimages/curl:latest \
      --restart=Never --rm --timeout=20s \
      -- curl -s --max-time 5 "$@" 2>&1 ) || true
}

# ---------------------------------------------------------------------------
# TEST NP-01: Ruch wychodzący do zewnętrznego IP
# ---------------------------------------------------------------------------
log_info "NP-01: Test ruchu wychodzącego do zewnętrznego IP (8.8.8.8)"
OUTPUT=""
OUTPUT=$(safe_run "nv-np-01" http://8.8.8.8)

if echo "${OUTPUT}" | grep -qi "connection refused\|timed out\|blocked\|forbidden\|exit code\|error\|failed" \
   || [[ -z "${OUTPUT}" ]]; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-01 Egress do zewnętrznego IP" "BLOCKED" \
    "Ruch do 8.8.8.8:80 zablokowany przez NeuVector Network Policy" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-01 Egress do zewnętrznego IP" "PASS" \
    "Ruch do zewnętrznego IP NIE zablokowany — weryfikuj politykę egress" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST NP-02: Ruch cross-namespace (do Kubernetes API)
# ---------------------------------------------------------------------------
log_info "NP-02: Test ruchu cross-namespace (${NS} → default)"
K8S_API_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.96.0.1")
OUTPUT=""
OUTPUT=$( ( kubectl run nv-np-02 \
  --namespace="${NS}" --image=curlimages/curl:latest \
  --restart=Never --rm --timeout=20s \
  -- curl -sk --max-time 5 "https://${K8S_API_IP}" 2>&1 ) || true )

if echo "${OUTPUT}" | grep -qi "timed out\|blocked\|forbidden\|refused\|unauthorized" \
   || [[ -z "${OUTPUT}" ]]; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-02 Cross-namespace (API Server)" "BLOCKED" \
    "Dostęp do Kubernetes API przez ClusterIP zablokowany" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-02 Cross-namespace (API Server)" "PASS" \
    "Dostęp do Kubernetes API z namespace sandbox nie jest ograniczony" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST NP-03: Port scan (niestandardowy port)
# ---------------------------------------------------------------------------
log_info "NP-03: Test połączenia na niestandardowy port (TARGET:9999)"
TARGET_POD_IP=$(kubectl get pod -n "${NS}" -l app=target-app \
  -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")

if [[ -z "${TARGET_POD_IP}" ]]; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-03 Port scan (9999)" "FAIL" \
    "Nie znaleziono Pod'a target-app w namespace ${NS}" ""
else
  OUTPUT=""
  OUTPUT=$( ( kubectl run nv-np-03 \
    --namespace="${NS}" --image=curlimages/curl:latest \
    --restart=Never --rm --timeout=20s \
    -- curl -s --max-time 5 "http://${TARGET_POD_IP}:9999" 2>&1 ) || true )

  if echo "${OUTPUT}" | grep -qi "refused\|blocked\|timed out" || [[ -z "${OUTPUT}" ]]; then
    result_add "${RESULTS_FILE}" "${MODULE}" "NP-03 Port scan (9999)" "BLOCKED" \
      "Połączenie na port 9999 zablokowane przez NeuVector" "${OUTPUT:0:300}"
  else
    result_add "${RESULTS_FILE}" "${MODULE}" "NP-03 Port scan (9999)" "PASS" \
      "Port 9999 dostępny — brak reguły blokującej niestandardowe porty" "${OUTPUT:0:300}"
  fi
fi

# ---------------------------------------------------------------------------
# TEST NP-04: Dozwolony ruch wewnętrzny (baseline)
# ---------------------------------------------------------------------------
log_info "NP-04: Test dozwolonego ruchu wewnętrznego (baseline)"
TARGET_SVC_NAME="${TARGET_SVC:-target-app}"
OUTPUT=""
OUTPUT=$( ( kubectl run nv-np-04 \
  --namespace="${NS}" --image=curlimages/curl:latest \
  --restart=Never --rm --timeout=20s \
  -- curl -s --max-time 5 "http://${TARGET_SVC_NAME}.${NS}.svc.cluster.local" 2>&1 ) || true )

if [[ -n "${OUTPUT}" ]] && ! echo "${OUTPUT}" | grep -qi "blocked\|forbidden\|timed out\|refused"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-04 Ruch wewnętrzny (baseline)" "PASS" \
    "Dozwolony ruch wewnętrzny działa poprawnie" "${OUTPUT:0:200}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-04 Ruch wewnętrzny (baseline)" "BLOCKED" \
    "Ruch wewnętrzny do target-app zablokowany (zbyt restrykcyjna polityka?)" "${OUTPUT:0:300}"
fi

log_ok "Moduł Network Policy zakończony"
