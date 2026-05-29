#!/usr/bin/env bash
# tests/04_runtime_process.sh
# Testuje Runtime Process Security NeuVector — uruchamia niedozwolone procesy
# w kontenerze i sprawdza czy NeuVector je blokuje.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="Runtime Process"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"

# Funkcja: exec polecenia w istniejącym podzie target-app lub tymczasowym
exec_in_target() {
  local cmd="$1"
  local TARGET_POD
  TARGET_POD=$(kubectl get pod -n "${NS}" -l app=target-app \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -n "${TARGET_POD}" ]]; then
    kubectl exec -n "${NS}" "${TARGET_POD}" -- sh -c "${cmd}" 2>&1
  else
    # Fallback: tymczasowy pod
    kubectl run "nv-rt-temp-$$" \
      --namespace="${NS}" \
      --image=alpine:latest \
      --restart=Never \
      --rm \
      --timeout=20s \
      -- sh -c "${cmd}" 2>&1
  fi
}

# ---------------------------------------------------------------------------
# TEST RT-01: Uruchomienie niedozwolonego procesu (netcat)
# ---------------------------------------------------------------------------
log_info "RT-01: Próba uruchomienia netcat (nc) w kontenerze"
EXIT_CODE=0
OUTPUT=$(exec_in_target "nc -z localhost 80 2>&1; echo exit_code:\$?") || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "blocked\|killed\|permission denied\|not found\|operation not permitted"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-01 Netcat (nc)" "BLOCKED" \
    "Uruchomienie netcat zablokowane przez NeuVector Process Profile" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-01 Netcat (nc)" "PASS" \
    "Netcat uruchomiony bez blokady — brak reguły process profile dla nc" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST RT-02: Odczyt /etc/shadow (privilege escalation attempt)
# ---------------------------------------------------------------------------
log_info "RT-02: Próba odczytu /etc/shadow"
EXIT_CODE=0
OUTPUT=$(exec_in_target "cat /etc/shadow 2>&1") || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "permission denied\|blocked\|no such file"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-02 Odczyt /etc/shadow" "BLOCKED" \
    "Dostęp do /etc/shadow zablokowany (permission denied lub NV block)" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-02 Odczyt /etc/shadow" "PASS" \
    "/etc/shadow odczytany — kontener działa jako root bez ograniczeń" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST RT-03: Uruchomienie curl/wget w kontenerze (exfiltration tool)
# ---------------------------------------------------------------------------
log_info "RT-03: Próba uruchomienia wget do zewnętrznego hosta"
EXIT_CODE=0
OUTPUT=$(exec_in_target "wget -q --timeout=5 -O /dev/null http://example.com 2>&1") || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "blocked\|killed\|permission denied\|network unreachable\|timed out"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-03 wget do zewnętrznego hosta" "BLOCKED" \
    "wget zablokowany — reguła process profile lub network policy egress" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-03 wget do zewnętrznego hosta" "PASS" \
    "wget do zewnętrznego hosta wykonany bez blokady" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST RT-04: Próba zapisu do /proc (kernel exploit attempt)
# ---------------------------------------------------------------------------
log_info "RT-04: Próba zapisu do /proc/sys/kernel"
EXIT_CODE=0
OUTPUT=$(exec_in_target "echo 0 > /proc/sys/kernel/dmesg_restrict 2>&1") || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "permission denied\|read-only\|operation not permitted\|blocked"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-04 Zapis do /proc/sys/kernel" "BLOCKED" \
    "Próba modyfikacji /proc/sys zablokowana (seccomp/NV/kernel)" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-04 Zapis do /proc/sys/kernel" "PASS" \
    "Zapis do /proc/sys/kernel dozwolony — brak ograniczeń seccomp" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST RT-05: Uruchomienie bash z SUID (privilege escalation)
# ---------------------------------------------------------------------------
log_info "RT-05: Próba uruchomienia bash jako SUID"
EXIT_CODE=0
OUTPUT=$(exec_in_target "chmod u+s /bin/sh 2>&1; ls -la /bin/sh 2>&1") || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "permission denied\|operation not permitted\|blocked"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-05 Ustawienie SUID na /bin/sh" "BLOCKED" \
    "Ustawienie bitu SUID zablokowane przez NeuVector lub kernel" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "RT-05 Ustawienie SUID na /bin/sh" "PASS" \
    "Bit SUID ustawiony bez blokady — kontener ma zbyt szerokie uprawnienia" "${OUTPUT:0:300}"
fi

log_ok "Moduł Runtime Process Security zakończony"
