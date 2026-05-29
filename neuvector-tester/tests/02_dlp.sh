#!/usr/bin/env bash
# tests/02_dlp.sh
# Testuje Data Loss Prevention — symuluje wyciek wrażliwych danych
# przez ruch sieciowy (numery kart, PESEL, tokeny API).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="DLP"
NS="${NAMESPACE:-neuvector-test}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"
TARGET_SVC_NAME="${TARGET_SVC:-target-app}"
TARGET_URL="http://${TARGET_SVC_NAME}.${NS}.svc.cluster.local"

run_curl_test() {
  local pod_name="$1"
  local url="$2"
  local data="$3"
  kubectl run "${pod_name}" \
    --namespace="${NS}" \
    --image=curlimages/curl:latest \
    --restart=Never \
    --rm \
    --timeout=20s \
    -- curl -s --max-time 8 -X POST "${url}" \
       -H "Content-Type: application/json" \
       -d "${data}" 2>&1
}

# ---------------------------------------------------------------------------
# TEST DLP-01: Numer karty kredytowej w ruchu HTTP
# ---------------------------------------------------------------------------
log_info "DLP-01: Wysyłanie numeru karty kredytowej w POST body"
EXIT_CODE=0
OUTPUT=$(run_curl_test "nv-dlp-01" "${TARGET_URL}/api/data" \
  '{"card":"4111111111111111","cvv":"123","expiry":"12/28"}') || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "blocked\|forbidden\|403\|reset"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-01 Numer karty kredytowej" "BLOCKED" \
    "Transmisja numeru karty (4111111111111111) zablokowana przez DLP" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-01 Numer karty kredytowej" "PASS" \
    "Numer karty kredytowej NIE został wykryty przez DLP" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST DLP-02: PESEL w ruchu HTTP
# ---------------------------------------------------------------------------
log_info "DLP-02: Wysyłanie numeru PESEL w POST body"
EXIT_CODE=0
OUTPUT=$(run_curl_test "nv-dlp-02" "${TARGET_URL}/api/user" \
  '{"name":"Jan Kowalski","pesel":"90010112345","address":"ul. Testowa 1"}') || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "blocked\|forbidden\|403\|reset"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-02 Numer PESEL" "BLOCKED" \
    "Transmisja numeru PESEL zablokowana przez DLP" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-02 Numer PESEL" "PASS" \
    "Numer PESEL NIE został wykryty przez DLP" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST DLP-03: Token API / secret w nagłówku HTTP
# ---------------------------------------------------------------------------
log_info "DLP-03: Wysyłanie tokenu API w nagłówku Authorization"
EXIT_CODE=0
OUTPUT=$(kubectl run nv-dlp-03 \
  --namespace="${NS}" \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm \
  --timeout=20s \
  -- curl -s --max-time 8 "${TARGET_URL}/api/secure" \
     -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiaWF0IjoxNjAwMDAwMDAwfQ.FAKE_SECRET_TOKEN" \
     -H "X-API-Key: sk-prod-FAKESECRET1234567890abcdef" 2>&1) || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "blocked\|forbidden\|403\|reset"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-03 Token API w nagłówku" "BLOCKED" \
    "Transmisja tokenu API/JWT zablokowana przez DLP" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-03 Token API w nagłówku" "PASS" \
    "Token API w nagłówku NIE został wykryty przez DLP" "${OUTPUT:0:300}"
fi

# ---------------------------------------------------------------------------
# TEST DLP-04: Dane SSN / paszport w ruchu
# ---------------------------------------------------------------------------
log_info "DLP-04: Wysyłanie numeru paszportu w body"
EXIT_CODE=0
OUTPUT=$(run_curl_test "nv-dlp-04" "${TARGET_URL}/api/identity" \
  '{"passport":"AB1234567","ssn":"123-45-6789","dob":"1990-01-01"}') || EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || echo "${OUTPUT}" | grep -qi "blocked\|forbidden\|403\|reset"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-04 Numer paszportu/SSN" "BLOCKED" \
    "Transmisja danych paszportowych/SSN zablokowana przez DLP" "${OUTPUT:0:300}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "DLP-04 Numer paszportu/SSN" "PASS" \
    "Dane paszportowe/SSN NIE zostały wykryte przez DLP" "${OUTPUT:0:300}"
fi

log_ok "Moduł DLP zakończony"
