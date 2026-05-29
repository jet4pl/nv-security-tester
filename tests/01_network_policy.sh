#!/usr/bin/env bash
# tests/01_network_policy.sh
# Testuje reguły segmentacji sieciowej NeuVector (Network Policy)
# Symuluje niedozwolony ruch między namespace'ami oraz do zewnętrznych IP.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="Network Policy"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"

# Funkcja pomocnicza: uruchom polecenie w tymczasowym pod'zie testowym
run_in_pod() {
  local pod_name="$1"
  local image="$2"
  shift 2
  kubectl run "${pod_name}" \
    --namespace="${NS}" \
    --image="${image}" \
    --restart=Never \
    --rm \
    --timeout=30s \
    -- "$@" 2>&1
}

# ---------------------------------------------------------------------------
# TEST NP-01: Ruch wychodzący do zewnętrznego IP (powinien być zablokowany)
# ---------------------------------------------------------------------------
log_info "NP-01: Test ruchu wychodzącego do zewnętrznego IP (8.8.8.8)"
EXIT_CODE=0
OUTPUT=$(kubectl run nv-np-01 \
  --namespace="${NS}" \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm \
  --timeout=20s \
  -- curl -s --max-time 5 http://8.8.8.8 2>&1) || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "connection refused\|timed out\|blocked\|forbidden"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-01 Egress do zewnętrznego IP" "BLOCKED" \
    "Ruch do 8.8.8.8:80 został zablokowany przez NeuVector Network Policy" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-01 Egress do zewnętrznego IP" "PASS" \
    "Ruch do zewnętrznego IP NIE został zablokowany — weryfikuj politykę egress" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST NP-02: Ruch między namespace'ami (cross-namespace)
# ---------------------------------------------------------------------------
log_info "NP-02: Test ruchu cross-namespace (${NS} → default)"
EXIT_CODE=0
# Pobierz ClusterIP serwisu kubernetes w namespace default
K8S_API_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.96.0.1")
OUTPUT=$(kubectl run nv-np-02 \
  --namespace="${NS}" \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm \
  --timeout=20s \
  -- curl -sk --max-time 5 "https://${K8S_API_IP}" 2>&1) || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "timed out\|blocked\|forbidden\|refused"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-02 Cross-namespace (API Server)" "BLOCKED" \
    "Bezpośredni dostęp do Kubernetes API przez ClusterIP zablokowany" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-02 Cross-namespace (API Server)" "PASS" \
    "Dostęp do Kubernetes API z namespace sandbox nie jest ograniczony" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST NP-03: Port scan (niedozwolone połączenie na niestandardowy port)
# ---------------------------------------------------------------------------
log_info "NP-03: Test połączenia na niestandardowy port (TARGET:9999)"
TARGET_POD_IP=$(kubectl get pod -n "${NS}" -l app=target-app \
  -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")

if [[ -z "${TARGET_POD_IP}" ]]; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-03 Port scan (9999)" "FAIL" \
    "Nie znaleziono Pod'a target-app w namespace ${NS} — pomiń lub wdróż target" ""
else
  EXIT_CODE=0
  OUTPUT=$(kubectl run nv-np-03 \
    --namespace="${NS}" \
    --image=curlimages/curl:latest \
    --restart=Never \
    --rm \
    --timeout=20s \
    -- curl -s --max-time 5 "http://${TARGET_POD_IP}:9999" 2>&1) || EXIT_CODE=$?

  if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "refused\|blocked\|timed out"; then
    result_add "${RESULTS_FILE}" "${MODULE}" "NP-03 Port scan (9999)" "BLOCKED" \
      "Połączenie na port 9999 zablokowane przez NeuVector" "${OUTPUT:0:300}"
  else
    result_add "${RESULTS_FILE}" "${MODULE}" "NP-03 Port scan (9999)" "PASS" \
      "Port 9999 dostępny — brak reguły blokującej niestandardowe porty" "${OUTPUT:0:300}"
  fi
fi

# ---------------------------------------------------------------------------
# TEST NP-04: Ruch wewnętrzny (dozwolony — baseline)
# ---------------------------------------------------------------------------
log_info "NP-04: Test dozwolonego ruchu wewnętrznego (baseline)"
TARGET_SVC_NAME="${TARGET_SVC:-target-app}"
EXIT_CODE=0
OUTPUT=$(kubectl run nv-np-04 \
  --namespace="${NS}" \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm \
  --timeout=20s \
  -- curl -s --max-time 5 "http://${TARGET_SVC_NAME}.${NS}.svc.cluster.local" 2>&1) || EXIT_CODE=$?

if [[ ${EXIT_CODE} -eq 0 ]] && ! echo "${OUTPUT}" | grep -qi "blocked\|forbidden"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-04 Ruch wewnętrzny (baseline)" "PASS" \
    "Dozwolony ruch wewnętrzny działa poprawnie" "${OUTPUT:0:200}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "NP-04 Ruch wewnętrzny (baseline)" "BLOCKED" \
    "Ruch wewnętrzny do target-app zablokowany (zbyt restrykcyjna polityka?)" "${OUTPUT:0:300}"
fi

log_ok "Moduł Network Policy zakończony"
