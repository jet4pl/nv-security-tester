#!/usr/bin/env bash
# lib/results.sh — zapis wyników do pliku CSV (bez jq)
# Format: STATUS|MODULE|NAME|DESCRIPTION|TIMESTAMP

results_init() {
  local file="$1"
  # Nagłówek + metadane jako komentarz
  printf "# NeuVector Security Test Suite\n" > "${file}"
  printf "# started_at=%s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "${file}"
  printf "# namespace=%s\n" "${NAMESPACE:-neuvector-test}" >> "${file}"
  printf "STATUS|MODULE|NAME|DESCRIPTION|TIMESTAMP\n" >> "${file}"
}

# result_add <file> <module> <name> <status> <description> [details]
result_add() {
  local file="$1"
  local module="$2"
  local test_name="$3"
  local status="$4"
  local description="$5"
  local timestamp
  timestamp="$(date -u +"%H:%M:%SZ")"

  # Escapuj pipe'y w polach
  module="${module//|/,}"
  test_name="${test_name//|/,}"
  description="${description//|/,}"

  printf "%s|%s|%s|%s|%s\n" \
    "${status}" "${module}" "${test_name}" "${description}" "${timestamp}" >> "${file}"

  # Logowanie do stdout
  case "${status}" in
    PASS)    printf "\033[0;32m  ✓ [PASS]\033[0m    %s: %s\n" "${test_name}" "${description}" ;;
    BLOCKED) printf "\033[1;33m  ✗ [BLOCKED]\033[0m %s: %s\n" "${test_name}" "${description}" ;;
    FAIL)    printf "\033[0;31m  ✗ [FAIL]\033[0m    %s: %s\n" "${test_name}" "${description}" ;;
    TIMEOUT) printf "\033[1;33m  ⏱ [TIMEOUT]\033[0m %s: %s\n" "${test_name}" "${description}" ;;
    *)       printf "  ? [%s] %s: %s\n" "${status}" "${test_name}" "${description}" ;;
  esac
}

results_finalize() {
  local file="$1"
  printf "# finished_at=%s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "${file}"
}

# Liczenie wyników z pliku CSV (bez jq)
count_status() {
  local file="$1"
  local status="$2"
  grep -c "^${status}|" "${file}" 2>/dev/null || echo 0
}

count_total() {
  local file="$1"
  grep -v "^#" "${file}" | grep -v "^STATUS" | grep -c "|" 2>/dev/null || echo 0
}
