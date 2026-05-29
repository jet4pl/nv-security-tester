#!/usr/bin/env bash
# =============================================================================
# NeuVector Security Test Suite — Orchestrator
# Uruchamia wszystkie moduły testowe sekwencyjnie, zbiera wyniki,
# generuje raport HTML. Każdy test jest izolowany — blokada NeuVector
# nie zatrzymuje kolejnych testów.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

# ---------------------------------------------------------------------------
# Konfiguracja
# ---------------------------------------------------------------------------
export NAMESPACE="${NAMESPACE:-neuvector-test}"
export TARGET_SVC="${TARGET_SVC:-target-app}"
export REPORT_DIR="${SCRIPT_DIR}/report"
export RESULTS_FILE="${REPORT_DIR}/results.json"
export TEST_TIMEOUT="${TEST_TIMEOUT:-60}"   # sekund na jeden test
export LOG_FILE="${REPORT_DIR}/run.log"

TESTS=(
  "01_network_policy"
  "02_dlp"
  "03_waf"
  "04_runtime_process"
  "05_vulnerability_scan"
  "06_compliance_cis"
)

TEST_LABELS=(
  "Network Policy"
  "DLP / Data Loss Prevention"
  "WAF (Web Application Firewall)"
  "Runtime Process Security"
  "Vulnerability Scanner"
  "Compliance / CIS Benchmarks"
)

# ---------------------------------------------------------------------------
# Inicjalizacja
# ---------------------------------------------------------------------------
mkdir -p "${REPORT_DIR}"
results_init "${RESULTS_FILE}"

log_banner "NeuVector Security Test Suite"
log_info "Namespace  : ${NAMESPACE}"
log_info "Target SVC : ${TARGET_SVC}"
log_info "Timeout    : ${TEST_TIMEOUT}s per test"
log_info "Wyniki     : ${RESULTS_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Pętla testowa — każdy test w subprocess z timeout
# ---------------------------------------------------------------------------
TOTAL=0
BLOCKED=0
PASSED=0
FAILED=0
TIMED_OUT=0

for i in "${!TESTS[@]}"; do
  TEST_ID="${TESTS[$i]}"
  TEST_LABEL="${TEST_LABELS[$i]}"
  TEST_SCRIPT="${SCRIPT_DIR}/tests/${TEST_ID}.sh"

  log_section "Moduł: ${TEST_LABEL}"

  if [[ ! -f "${TEST_SCRIPT}" ]]; then
    log_warn "Brak skryptu: ${TEST_SCRIPT} — pomijam"
    continue
  fi

  chmod +x "${TEST_SCRIPT}"

  # Uruchom test w podprocesie z limitem czasu
  # Wyniki każdego sub-testu dopisywane są do RESULTS_FILE przez sam skrypt
  EXIT_CODE=0
  timeout "${TEST_TIMEOUT}" bash "${TEST_SCRIPT}" 2>&1 | tee -a "${LOG_FILE}" || EXIT_CODE=$?

  case ${EXIT_CODE} in
    0)   log_ok  "Moduł ${TEST_LABEL}: zakończony" ;;
    124) log_warn "Moduł ${TEST_LABEL}: TIMEOUT (>${TEST_TIMEOUT}s)" ; ((TIMED_OUT++)) ;;
    *)   log_warn "Moduł ${TEST_LABEL}: zakończony z kodem ${EXIT_CODE}" ;;
  esac

  echo ""
  ((TOTAL++)) || true
done

# ---------------------------------------------------------------------------
# Podsumowanie wyników z pliku JSON
# ---------------------------------------------------------------------------
BLOCKED=$(jq '[.tests[] | select(.status=="BLOCKED")] | length' "${RESULTS_FILE}")
PASSED=$(jq '[.tests[] | select(.status=="PASS")] | length' "${RESULTS_FILE}")
FAILED=$(jq '[.tests[] | select(.status=="FAIL")] | length' "${RESULTS_FILE}")
TIMEOUT_COUNT=$(jq '[.tests[] | select(.status=="TIMEOUT")] | length' "${RESULTS_FILE}")
TOTAL_TESTS=$(jq '.tests | length' "${RESULTS_FILE}")

results_finalize "${RESULTS_FILE}" "${TOTAL_TESTS}" "${PASSED}" "${BLOCKED}" "${FAILED}" "${TIMEOUT_COUNT}"

log_banner "PODSUMOWANIE"
log_info "Łącznie testów  : ${TOTAL_TESTS}"
log_ok   "PASS (nie wykryto / dozwolone) : ${PASSED}"
log_warn "BLOCKED (zablokowane przez NV) : ${BLOCKED}"
log_fail "FAIL (błąd testu)              : ${FAILED}"
log_warn "TIMEOUT                        : ${TIMEOUT_COUNT}"

# ---------------------------------------------------------------------------
# Generowanie raportu HTML
# ---------------------------------------------------------------------------
log_info "Generowanie raportu HTML..."
bash "${SCRIPT_DIR}/report/generate_report.sh" "${RESULTS_FILE}" "${REPORT_DIR}/report.html"
log_ok "Raport: ${REPORT_DIR}/report.html"
log_info "Pobierz raport: kubectl cp \${POD_NAME}:${REPORT_DIR}/report.html ./neuvector_report.html"
