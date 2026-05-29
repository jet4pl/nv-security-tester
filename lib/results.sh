#!/usr/bin/env bash
# lib/results.sh — zarządzanie wynikami testów w formacie JSON

results_init() {
  local file="$1"
  cat > "${file}" <<EOF
{
  "suite": "NeuVector Security Test Suite",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "cluster_namespace": "${NAMESPACE:-neuvector-test}",
  "tests": [],
  "summary": {}
}
EOF
}

# Dodaj wynik pojedynczego testu
# Użycie: result_add <plik> <moduł> <nazwa_testu> <status> <opis> [szczegóły]
# Status: PASS | BLOCKED | FAIL | TIMEOUT
result_add() {
  local file="$1"
  local module="$2"
  local test_name="$3"
  local status="$4"
  local description="$5"
  local details="${6:-}"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local entry
  entry=$(jq -n \
    --arg module "${module}" \
    --arg name "${test_name}" \
    --arg status "${status}" \
    --arg desc "${description}" \
    --arg details "${details}" \
    --arg ts "${timestamp}" \
    '{module: $module, name: $name, status: $status, description: $desc, details: $details, timestamp: $ts}')

  local tmp
  tmp=$(mktemp)
  jq ".tests += [${entry}]" "${file}" > "${tmp}" && mv "${tmp}" "${file}"

  # Logowanie do stdout
  case "${status}" in
    PASS)    echo -e "\033[0;32m  ✓ [PASS]\033[0m    ${test_name}: ${description}" ;;
    BLOCKED) echo -e "\033[1;33m  ✗ [BLOCKED]\033[0m ${test_name}: ${description}" ;;
    FAIL)    echo -e "\033[0;31m  ✗ [FAIL]\033[0m    ${test_name}: ${description}" ;;
    TIMEOUT) echo -e "\033[1;33m  ⏱ [TIMEOUT]\033[0m ${test_name}: ${description}" ;;
    *)       echo -e "  ? [${status}] ${test_name}: ${description}" ;;
  esac
}

results_finalize() {
  local file="$1"
  local total="$2"
  local passed="$3"
  local blocked="$4"
  local failed="$5"
  local timed_out="$6"
  local finished_at
  finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local tmp
  tmp=$(mktemp)
  jq \
    --arg fa "${finished_at}" \
    --argjson total "${total}" \
    --argjson passed "${passed}" \
    --argjson blocked "${blocked}" \
    --argjson failed "${failed}" \
    --argjson timed_out "${timed_out}" \
    '.finished_at = $fa |
     .summary = {
       total: $total,
       passed: $passed,
       blocked: $blocked,
       failed: $failed,
       timed_out: $timed_out
     }' \
    "${file}" > "${tmp}" && mv "${tmp}" "${file}"
}
