#!/usr/bin/env bash
# =============================================================================
# NeuVector Security Test Suite — Orchestrator
# WAŻNE: celowo BEZ set -e i BEZ pipe między timeout a tee.
# NeuVector w trybie Protect może wysłać SIGKILL (exit 137) do podprocesów.
# Każdy moduł jest izolowany w osobnej podpowłoce — orchestrator zawsze
# kontynuuje niezależnie od wyniku modułu.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

export NAMESPACE="${NAMESPACE:-neuvector-test}"
export TARGET_SVC="${TARGET_SVC:-target-app}"
export REPORT_DIR="/report"
export RESULTS_FILE="${REPORT_DIR}/results.json"
export TEST_TIMEOUT="${TEST_TIMEOUT:-90}"
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

mkdir -p "${REPORT_DIR}"
results_init "${RESULTS_FILE}"

log_banner "NeuVector Security Test Suite"
log_info "Namespace  : ${NAMESPACE}"
log_info "Target SVC : ${TARGET_SVC}"
log_info "Timeout    : ${TEST_TIMEOUT}s per moduł"
log_info "Wyniki     : ${RESULTS_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Pętla testowa
# Kluczowe: NIE używamy pipe (cmd | tee) — zamiast tego:
#   1. Uruchom moduł z przekierowaniem do pliku tymczasowego
#   2. cat pliku po zakończeniu
# Dzięki temu SIGKILL z NeuVector nie propaguje się do orchestratora.
# ---------------------------------------------------------------------------
for i in "${!TESTS[@]}"; do
  TEST_ID="${TESTS[$i]}"
  TEST_LABEL="${TEST_LABELS[$i]}"
  TEST_SCRIPT="${SCRIPT_DIR}/tests/${TEST_ID}.sh"

  log_section "Moduł: ${TEST_LABEL}"

  if [[ ! -f "${TEST_SCRIPT}" ]]; then
    log_warn "Brak pliku: ${TEST_SCRIPT} — pomijam"
    continue
  fi

  # Plik tymczasowy na output modułu — unikamy pipe
  MODULE_LOG=$(mktemp /tmp/nv_mod_XXXXXX.log)
  EXIT_CODE=0

  # Podpowłoka + timeout + przekierowanie do pliku (nie pipe!)
  # Podpowłoka () sprawia że nawet jeśli timeout zostanie SIGKILL'd,
  # orchestrator to przeżyje i złapie exit code przez || EXIT_CODE=$?
  (
    timeout "${TEST_TIMEOUT}" bash "${TEST_SCRIPT}"
  ) > "${MODULE_LOG}" 2>&1 || EXIT_CODE=$?

  # Wyświetl i zapisz output modułu
  cat "${MODULE_LOG}"
  cat "${MODULE_LOG}" >> "${LOG_FILE}" 2>/dev/null || true
  rm -f "${MODULE_LOG}"

  # Obsługa wszystkich możliwych exit code'ów
  case ${EXIT_CODE} in
    0)
      log_ok "Moduł ${TEST_LABEL}: zakończony pomyślnie"
      ;;
    124)
      log_warn "Moduł ${TEST_LABEL}: TIMEOUT (>${TEST_TIMEOUT}s) — kontynuuję"
      result_add "${RESULTS_FILE}" "${TEST_LABEL}" "Moduł-TIMEOUT" "TIMEOUT" \
        "Cały moduł przekroczył timeout ${TEST_TIMEOUT}s" ""
      ;;
    137)
      # SIGKILL — NeuVector zabił cały skrypt modułu, nie tylko podproces
      log_warn "Moduł ${TEST_LABEL}: SIGKILL od NeuVector (kod 137) — kontynuuję"
      result_add "${RESULTS_FILE}" "${TEST_LABEL}" "Moduł-SIGKILL" "BLOCKED" \
        "NeuVector wysłał SIGKILL do całego skryptu modułu (kod 137) — wszystkie testy w module zablokowane" \
        "Zrestartuj moduł z mniejszym TEST_TIMEOUT lub w trybie Monitor"
      ;;
    *)
      log_warn "Moduł ${TEST_LABEL}: zakończony z kodem ${EXIT_CODE} — kontynuuję"
      ;;
  esac

  echo ""
done

# ---------------------------------------------------------------------------
# Podsumowanie i raport
# ---------------------------------------------------------------------------
BLOCKED=$(jq '[.tests[] | select(.status=="BLOCKED")] | length' "${RESULTS_FILE}")
PASSED=$(jq  '[.tests[] | select(.status=="PASS")]    | length' "${RESULTS_FILE}")
FAILED=$(jq  '[.tests[] | select(.status=="FAIL")]    | length' "${RESULTS_FILE}")
TIMEOUT_COUNT=$(jq '[.tests[] | select(.status=="TIMEOUT")] | length' "${RESULTS_FILE}")
TOTAL_TESTS=$(jq '.tests | length' "${RESULTS_FILE}")

results_finalize "${RESULTS_FILE}" "${TOTAL_TESTS}" "${PASSED}" "${BLOCKED}" "${FAILED}" "${TIMEOUT_COUNT}"

log_banner "PODSUMOWANIE"
log_info "Łącznie testów  : ${TOTAL_TESTS}"
log_ok   "PASS (atak nie zablokowany) : ${PASSED}"
log_warn "BLOCKED (NeuVector block)   : ${BLOCKED}"
log_fail "FAIL (błąd środowiska)      : ${FAILED}"
log_warn "TIMEOUT                     : ${TIMEOUT_COUNT}"

log_info "Generowanie raportu HTML..."
bash "${SCRIPT_DIR}/report/generate_report.sh" "${RESULTS_FILE}" "${REPORT_DIR}/report.html"
log_ok "Raport gotowy: ${REPORT_DIR}/report.html"
log_info ""
log_info "Pobierz raport:"
log_info "  POD=\$(kubectl get pod -n ${NAMESPACE} -l app=nv-security-tester -o jsonpath='{.items[0].metadata.name}')"
log_info "  kubectl cp ${NAMESPACE}/\${POD}:${REPORT_DIR}/report.html ./raport_neuvector.html"
