#!/usr/bin/env bash
# tests/03_waf.sh
# Testuje WAF NeuVector — symuluje typowe ataki webowe:
# SQL Injection, XSS, Path Traversal, Command Injection, Log4Shell (bezpieczna symulacja)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="WAF"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"
TARGET_SVC_NAME="${TARGET_SVC:-target-app}"
TARGET_URL="http://${TARGET_SVC_NAME}.${NS}.svc.cluster.local"

waf_curl() {
  local pod_name="$1"
  local url="$2"
  shift 2
  kubectl run "${pod_name}" \
    --namespace="${NS}" \
    --image=curlimages/curl:latest \
    --restart=Never \
    --rm \
    --timeout=20s \
    -- curl -s --max-time 8 "$@" "${url}" 2>&1
}

check_blocked() {
  local exit_code="$1"
  local output="$2"
  [[ ${exit_code} -ne 0 ]] || echo "${output}" | grep -qi "blocked\|forbidden\|403\|400\|reset\|waf"
}

# ---------------------------------------------------------------------------
# TEST WAF-01: SQL Injection
# ---------------------------------------------------------------------------
log_info "WAF-01: SQL Injection (GET param)"
EXIT_CODE=0
OUTPUT=$(waf_curl "nv-waf-01" \
  "${TARGET_URL}/api/users?id=1%20OR%201%3D1%20--" \
  -H "User-Agent: Mozilla/5.0") || EXIT_CODE=$?

if check_blocked "${EXIT_CODE}" "${OUTPUT}"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-01 SQL Injection" "BLOCKED" \
    "Payload SQLi (1 OR 1=1 --) zablokowany przez WAF" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-01 SQL Injection" "PASS" \
    "Payload SQLi NIE został zablokowany przez WAF" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST WAF-02: XSS (Cross-Site Scripting)
# ---------------------------------------------------------------------------
log_info "WAF-02: XSS payload w parametrze GET"
EXIT_CODE=0
OUTPUT=$(waf_curl "nv-waf-02" \
  "${TARGET_URL}/search?q=%3Cscript%3Ealert%28%27xss%27%29%3C%2Fscript%3E" \
  -H "Referer: http://evil.example.com") || EXIT_CODE=$?

if check_blocked "${EXIT_CODE}" "${OUTPUT}"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-02 XSS (script tag)" "BLOCKED" \
    "Payload XSS (<script>alert</script>) zablokowany przez WAF" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-02 XSS (script tag)" "PASS" \
    "Payload XSS NIE został zablokowany przez WAF" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST WAF-03: Path Traversal
# ---------------------------------------------------------------------------
log_info "WAF-03: Path Traversal (../../../etc/passwd)"
EXIT_CODE=0
OUTPUT=$(waf_curl "nv-waf-03" \
  "${TARGET_URL}/files/../../../../etc/passwd") || EXIT_CODE=$?

if check_blocked "${EXIT_CODE}" "${OUTPUT}"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-03 Path Traversal" "BLOCKED" \
    "Próba path traversal (../etc/passwd) zablokowana przez WAF" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-03 Path Traversal" "PASS" \
    "Path traversal NIE został zablokowany przez WAF" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST WAF-04: Command Injection w POST body
# ---------------------------------------------------------------------------
log_info "WAF-04: Command Injection w POST body"
EXIT_CODE=0
OUTPUT=$(waf_curl "nv-waf-04" \
  "${TARGET_URL}/api/exec" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"cmd":"ping -c 1 localhost; cat /etc/passwd"}') || EXIT_CODE=$?

if check_blocked "${EXIT_CODE}" "${OUTPUT}"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-04 Command Injection" "BLOCKED" \
    "Payload command injection (cmd=...;cat /etc/passwd) zablokowany" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-04 Command Injection" "PASS" \
    "Command injection NIE został zablokowany przez WAF" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST WAF-05: Log4Shell (CVE-2021-44228) — bezpieczna symulacja payloadu w nagłówku
# ---------------------------------------------------------------------------
log_info "WAF-05: Log4Shell symulacja (bezpieczny payload w nagłówku User-Agent)"
EXIT_CODE=0
# Payload jest syntaktycznie podobny do Log4Shell ale wskazuje na localhost (brak exfil)
OUTPUT=$(waf_curl "nv-waf-05" \
  "${TARGET_URL}/" \
  -H 'User-Agent: ${jndi:ldap://127.0.0.1:1389/a}' \
  -H 'X-Api-Version: ${jndi:dns://127.0.0.1/test}') || EXIT_CODE=$?

if check_blocked "${EXIT_CODE}" "${OUTPUT}"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-05 Log4Shell (nagłówek)" "BLOCKED" \
    "Payload Log4Shell w User-Agent zablokowany przez WAF" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-05 Log4Shell (nagłówek)" "PASS" \
    "Payload Log4Shell NIE wykryty w nagłówkach HTTP przez WAF" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST WAF-06: SSRF (Server-Side Request Forgery)
# ---------------------------------------------------------------------------
log_info "WAF-06: SSRF — próba wymuszonego żądania do metadanych cloud"
EXIT_CODE=0
OUTPUT=$(waf_curl "nv-waf-06" \
  "${TARGET_URL}/api/fetch?url=http://169.254.169.254/latest/meta-data/") || EXIT_CODE=$?

if check_blocked "${EXIT_CODE}" "${OUTPUT}"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-06 SSRF (cloud metadata)" "BLOCKED" \
    "Próba SSRF do 169.254.169.254 zablokowana przez WAF" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "WAF-06 SSRF (cloud metadata)" "PASS" \
    "SSRF do cloud metadata NIE został zablokowany przez WAF" "${OUTPUT:0:300}"
fi

log_ok "Moduł WAF zakończony"
