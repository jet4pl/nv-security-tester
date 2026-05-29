#!/usr/bin/env bash
# tests/04_runtime_process.sh — Runtime Process Security
# NeuVector w trybie Protect może SIGKILL procesy exec w kontenerze.
# Każdy test w izolowanej podpowłoce — kod 137 = BLOCKED.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="Runtime Process"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"

# ---------------------------------------------------------------------------
# Pomocnik: exec polecenia w tymczasowym Pod'zie, izolowany
# exit 137 = SIGKILL od NeuVector = BLOCKED
# ---------------------------------------------------------------------------
rt_test() {
  local test_id="$1"
  local test_name="$2"
  local cmd="$3"
  local pod_suffix
  pod_suffix="nv-rt-$(echo "${test_id}" | tr '[:upper:]' '[:lower:]' | tr -d '-')-$$"

  local output exit_code
  exit_code=0

  # Podpowłoka izoluje SIGKILL
  output=$(
    (
      kubectl run "${pod_suffix}" \
        --namespace="${NS}" \
        --image=alpine:latest \
        --restart=Never \
        --rm \
        --timeout=25s \
        -- sh -c "${cmd}" 2>&1
    )
  ) || exit_code=$?

  # Cleanup
  kubectl delete pod "${pod_suffix}" -n "${NS}" \
    --ignore-not-found --grace-period=0 >/dev/null 2>&1 &

  local status desc
  if [[ ${exit_code} -eq 137 ]]; then
    status="BLOCKED"
    desc="NeuVector wysłał SIGKILL (kod 137) — proces zablokowany agresywnie przez Runtime Policy"
  elif [[ ${exit_code} -ne 0 ]] \
    || echo "${output}" | grep -qi "permission denied\|operation not permitted\|blocked\|killed"; then
    status="BLOCKED"
    desc="Operacja zablokowana (exit=${exit_code})"
  else
    status="PASS"
    desc="Operacja NIE zablokowana — weryfikuj Process Profile"
  fi

  result_add "${RESULTS_FILE}" "${MODULE}" "${test_id} ${test_name}" "${status}" \
    "${desc}" "${output:0:200}"
}

# ---------------------------------------------------------------------------
# RT-01: netcat
# ---------------------------------------------------------------------------
log_info "RT-01: Uruchomienie netcat w kontenerze"
rt_test "RT-01" "Netcat (nc)" \
  "which nc && nc -z localhost 80; echo done"

# ---------------------------------------------------------------------------
# RT-02: /etc/shadow
# ---------------------------------------------------------------------------
log_info "RT-02: Odczyt /etc/shadow"
rt_test "RT-02" "Odczyt /etc/shadow" \
  "cat /etc/shadow 2>&1 | head -3"

# ---------------------------------------------------------------------------
# RT-03: wget zewnętrzny
# ---------------------------------------------------------------------------
log_info "RT-03: wget do zewnętrznego hosta"
rt_test "RT-03" "wget do zewnętrznego hosta" \
  "wget -q --timeout=5 -O /dev/null http://example.com 2>&1; echo exit:\$?"

# ---------------------------------------------------------------------------
# RT-04: zapis do /proc/sys
# ---------------------------------------------------------------------------
log_info "RT-04: Zapis do /proc/sys/kernel"
rt_test "RT-04" "Zapis /proc/sys/kernel" \
  "echo 0 > /proc/sys/kernel/dmesg_restrict 2>&1; echo exit:\$?"

# ---------------------------------------------------------------------------
# RT-05: SUID na /bin/sh
# ---------------------------------------------------------------------------
log_info "RT-05: chmod SUID na /bin/sh"
rt_test "RT-05" "Ustawienie SUID /bin/sh" \
  "chmod u+s /bin/sh 2>&1; ls -la /bin/sh"

log_ok "Moduł Runtime Process Security zakończony"
