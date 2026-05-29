#!/usr/bin/env bash
# tests/03_waf.sh — WAF tests
# KLUCZOWE: każdy kubectl run w osobnej podpowłoce z własnym timeout.
# NeuVector może wysłać SIGKILL do podprocesu kubectl — izolujemy to
# tak żeby nie zabiło całego modułu.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="WAF"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"
TARGET_SVC_NAME="${TARGET_SVC:-target-app}"
TARGET_URL="http://${TARGET_SVC_NAME}.${NS}.svc.cluster.local"

# ---------------------------------------------------------------------------
# Pomocnik: uruchom curl w jednorazowym Pod'zie, izolowany od SIGKILL
# Zwraca: 0 = sukces połączenia, 1 = błąd/blokada
# ---------------------------------------------------------------------------
waf_test() {
  local pod_name="$1"
  local description="$2"
  local test_id="$3"
  shift 3
  # Wszystko w podpowłoce — SIGKILL od NeuVector nie wydostanie się wyżej
  local output exit_code
  exit_code=0
  output=$(
    (
      kubectl run "${pod_name}" \
        --namespace="${NS}" \
        --image=curlimages/curl:latest \
        --restart=Never \
        --rm \
        --timeout=25s \
        -- "$@" 2>&1
    )
  ) || exit_code=$?

  # Cleanup na wypadek gdyby Pod utknął (NeuVector kill)
  kubectl delete pod "${pod_name}" -n "${NS}" --ignore-not-found --grace-period=0 \
    >/dev/null 2>&1 &

  local blocked=false
  if [[ ${exit_code} -ne 0 ]] \
    || echo "${output}" | grep -qi "blocked\|forbidden\|403\|400 bad\|reset by peer\|connection reset\|waf\|Killed"; then
    blocked=true
  fi

  if $blocked; then
    result_add "${RESULTS_FILE}" "${MODULE}" "${test_id} ${description}" "BLOCKED" \
      "Atak zablokowany przez NeuVector WAF" "${output:0:200}"
  else
    result_add "${RESULTS_FILE}" "${MODULE}" "${test_id} ${description}" "PASS" \
      "Atak NIE został zablokowany przez WAF — weryfikuj reguły" "${output:0:200}"
  fi
}

# ---------------------------------------------------------------------------
# WAF-01: SQL Injection
# ---------------------------------------------------------------------------
log_info "WAF-01: SQL Injection"
waf_test "nv-waf-01" "SQL Injection" "WAF-01" \
  curl -s --max-time 8 \
  "${TARGET_URL}/api/users?id=1%20OR%201%3D1%20--" \
  -H "User-Agent: Mozilla/5.0"

# ---------------------------------------------------------------------------
# WAF-02: XSS
# ---------------------------------------------------------------------------
log_info "WAF-02: XSS payload"
waf_test "nv-waf-02" "XSS (script tag)" "WAF-02" \
  curl -s --max-time 8 \
  "${TARGET_URL}/search?q=%3Cscript%3Ealert%28%27xss%27%29%3C%2Fscript%3E"

# ---------------------------------------------------------------------------
# WAF-03: Path Traversal
# ---------------------------------------------------------------------------
log_info "WAF-03: Path Traversal"
waf_test "nv-waf-03" "Path Traversal (../etc/passwd)" "WAF-03" \
  curl -s --max-time 8 \
  "${TARGET_URL}/files/../../../../etc/passwd"

# ---------------------------------------------------------------------------
# WAF-04: Command Injection — uruchamiamy w osobnej podpowłoce z timeout
# Ten test jest najbardziej agresywny — NeuVector może SIGKILL kubectl
# ---------------------------------------------------------------------------
log_info "WAF-04: Command Injection"
CI_EXIT=0
CI_OUT=$(
  (
    kubectl run nv-waf-04 \
      --namespace="${NS}" \
      --image=curlimages/curl:latest \
      --restart=Never \
      --rm \
      --timeout=25s \
      -- curl -s --max-time 8 \
         -X POST "${TARGET_URL}/api/exec" \
         -H "Content-Type: application/json" \
         -d '{"cmd":"ping -c1 localhost; id"}' 2>&1
  )
) || CI_EXIT=$?
kubectl delete pod nv-waf-04 -n "${NS}" --ignore-not-found --grace-period=0 >/dev/null 2>&1 &

if [[ ${CI_EXIT} -eq 137 ]]; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-04 Command Injection" "BLOCKED" \
    "NeuVector wysłał SIGKILL do procesu kubectl (kod 137) — atak zablokowany agresywnie" \
    "exit_code=137"
elif [[ ${CI_EXIT} -ne 0 ]] || echo "${CI_OUT}" | grep -qi "blocked\|forbidden\|403\|reset"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-04 Command Injection" "BLOCKED" \
    "Command injection zablokowany przez WAF" "${CI_OUT:0:200}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-04 Command Injection" "PASS" \
    "Command injection NIE zablokowany przez WAF" "${CI_OUT:0:200}"
fi

# ---------------------------------------------------------------------------
# WAF-05: Log4Shell symulacja
# ---------------------------------------------------------------------------
log_info "WAF-05: Log4Shell (nagłówek)"
waf_test "nv-waf-05" "Log4Shell (User-Agent)" "WAF-05" \
  curl -s --max-time 8 "${TARGET_URL}/" \
  -H 'User-Agent: ${jndi:ldap://127.0.0.1:1389/a}' \
  -H 'X-Api-Version: ${jndi:dns://127.0.0.1/test}'

# ---------------------------------------------------------------------------
# WAF-06: SSRF
# ---------------------------------------------------------------------------
log_info "WAF-06: SSRF cloud metadata"
waf_test "nv-waf-06" "SSRF (169.254.169.254)" "WAF-06" \
  curl -s --max-time 8 \
  "${TARGET_URL}/api/fetch?url=http://169.254.169.254/latest/meta-data/"

log_ok "Moduł WAF zakończony"
