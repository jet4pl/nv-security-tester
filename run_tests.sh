#!/usr/bin/env bash
# =============================================================================
# NeuVector Security Test Suite — Orchestrator
# Bez jq, bez pipe — kompatybilny z NeuVector tryb Protect
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

export NAMESPACE="${NAMESPACE:-neuvector-test}"
export TARGET_SVC="${TARGET_SVC:-target-app}"
export REPORT_DIR="/report"
export RESULTS_FILE="${REPORT_DIR}/results.csv"
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
echo ""

# ---------------------------------------------------------------------------
# Pętla testowa — redirect zamiast pipe, podpowłoka absorbuje SIGKILL
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

  MODULE_LOG="${REPORT_DIR}/module_${TEST_ID}.log"
  EXIT_CODE=0

  ( timeout "${TEST_TIMEOUT}" bash "${TEST_SCRIPT}" ) > "${MODULE_LOG}" 2>&1 || EXIT_CODE=$?

  cat "${MODULE_LOG}"
  cat "${MODULE_LOG}" >> "${LOG_FILE}" 2>/dev/null || true

  case ${EXIT_CODE} in
    0)   log_ok  "Moduł ${TEST_LABEL}: zakończony" ;;
    124) log_warn "Moduł ${TEST_LABEL}: TIMEOUT"
         result_add "${RESULTS_FILE}" "${TEST_LABEL}" "Moduł-TIMEOUT" "TIMEOUT" \
           "Cały moduł przekroczył timeout ${TEST_TIMEOUT}s" ;;
    137) log_warn "Moduł ${TEST_LABEL}: SIGKILL (kod 137) — NeuVector zablokował moduł"
         result_add "${RESULTS_FILE}" "${TEST_LABEL}" "Moduł-SIGKILL" "BLOCKED" \
           "NeuVector SIGKILL na cały skrypt modułu" ;;
    *)   log_warn "Moduł ${TEST_LABEL}: kod ${EXIT_CODE}" ;;
  esac

  echo ""
done

results_finalize "${RESULTS_FILE}"

# ---------------------------------------------------------------------------
# Liczenie wyników — czysty bash/grep, zero jq
# ---------------------------------------------------------------------------
BLOCKED=$(count_status "${RESULTS_FILE}" "BLOCKED")
PASSED=$(count_status  "${RESULTS_FILE}" "PASS")
FAILED=$(count_status  "${RESULTS_FILE}" "FAIL")
TIMEOUT_COUNT=$(count_status "${RESULTS_FILE}" "TIMEOUT")
TOTAL_TESTS=$(count_total "${RESULTS_FILE}")

STARTED=$(grep "^# started_at=" "${RESULTS_FILE}" | cut -d= -f2)
FINISHED=$(grep "^# finished_at=" "${RESULTS_FILE}" | cut -d= -f2)

# ---------------------------------------------------------------------------
# Raport Markdown wyświetlany w konsoli (kopiowalny)
# ---------------------------------------------------------------------------
cat << MDEOF

$(printf '=%.0s' {1..60})
# NEUVECTOR SECURITY TEST REPORT
$(printf '=%.0s' {1..60})

**Suite:** NeuVector Security Test Suite
**Namespace:** ${NAMESPACE}
**Start:** ${STARTED}
**Koniec:** ${FINISHED}
**Tryb NeuVector:** Protect

## Podsumowanie

| Status   | Liczba | Znaczenie                            |
|----------|--------|--------------------------------------|
| BLOCKED  | ${BLOCKED}      | Ataki zablokowane przez NeuVector    |
| PASS     | ${PASSED}      | Ataki niezablokowane / testy bazowe  |
| FAIL     | ${FAILED}      | Błąd środowiskowy testu              |
| TIMEOUT  | ${TIMEOUT_COUNT}      | Przekroczono limit czasu             |
| **ŁĄCZNIE** | **${TOTAL_TESTS}** |                                  |

## Wyniki per test

| Status | Moduł | Test | Opis | Czas |
|--------|-------|------|------|------|
MDEOF

# Wiersze tabeli z CSV
while IFS='|' read -r status module name desc ts; do
  [[ "${status}" == "STATUS" ]] && continue
  [[ "${status}" == \#* ]]      && continue
  printf "| %-8s | %-25s | %-35s | %-55s | %s |\n" \
    "${status}" "${module}" "${name}" "${desc}" "${ts}"
done < <(grep -v "^#" "${RESULTS_FILE}")

cat << MDEOF2

$(printf '=%.0s' {1..60})

> Raport wygenerowany: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
> Skopiuj powyższy tekst lub pobierz plik CSV:
>   kubectl cp \${POD}:/report/results.csv ./neuvector_results.csv

$(printf '=%.0s' {1..60})
MDEOF2

log_ok "Test suite zakończony."
