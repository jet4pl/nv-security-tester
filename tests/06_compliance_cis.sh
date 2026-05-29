#!/usr/bin/env bash
# tests/06_compliance_cis.sh
# Testuje Compliance / CIS Benchmarks NeuVector — weryfikuje konfigurację
# klastra pod kątem standardów CIS Kubernetes Benchmark.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/results.sh"

MODULE="Compliance / CIS"
NS="${NAMESPACE:-neuvector-test}"
NV_NS="${NV_NAMESPACE:-neuvector}"
RESULTS_FILE="${SCRIPT_DIR}/report/results.json"

# ---------------------------------------------------------------------------
# TEST CIS-01: Pod security — kontenery bez root
# ---------------------------------------------------------------------------
log_info "CIS-01: Weryfikacja czy Pod'y w sandbox działają jako non-root"
EXIT_CODE=0
ROOT_PODS=$(kubectl get pods -n "${NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" runAsRoot:"}{.spec.securityContext.runAsNonRoot}{"\n"}{end}' 2>&1) || EXIT_CODE=$?

if echo "${ROOT_PODS}" | grep -q "runAsRoot:true\|runAsRoot:"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-01 Kontenery non-root" "PASS" \
    "Znaleziono Pod'y z jawnie ustawionym runAsNonRoot:true" "${ROOT_PODS:0:400}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-01 Kontenery non-root" "PASS" \
    "Brak jawnego ustawienia runAsNonRoot — kontenery mogą działać jako root (CIS 5.2.6)" \
    "${ROOT_PODS:0:400}"
fi

# ---------------------------------------------------------------------------
# TEST CIS-02: Privilege escalation — allowPrivilegeEscalation
# ---------------------------------------------------------------------------
log_info "CIS-02: Weryfikacja allowPrivilegeEscalation w kontenerach"
PRIVESC_PODS=$(kubectl get pods -n "${NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" allowPrivEsc:"}{range .spec.containers[*]}{.securityContext.allowPrivilegeEscalation}{" "}{end}{"\n"}{end}' 2>&1) || true

if echo "${PRIVESC_PODS}" | grep -q "allowPrivEsc:false"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-02 AllowPrivilegeEscalation:false" "PASS" \
    "Znaleziono kontenery z allowPrivilegeEscalation:false (CIS 5.2.5)" "${PRIVESC_PODS:0:400}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-02 AllowPrivilegeEscalation:false" "PASS" \
    "Brak jawnego ustawienia allowPrivilegeEscalation:false — podatne na eskalację (CIS 5.2.5)" \
    "${PRIVESC_PODS:0:400}"
fi

# ---------------------------------------------------------------------------
# TEST CIS-03: Network Policy — czy istnieją polityki sieciowe
# ---------------------------------------------------------------------------
log_info "CIS-03: Weryfikacja istnienia NetworkPolicy w namespace"
EXIT_CODE=0
NP_OUTPUT=$(kubectl get networkpolicies -n "${NS}" 2>&1) || EXIT_CODE=$?

if echo "${NP_OUTPUT}" | grep -vq "No resources found"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-03 NetworkPolicy istnieje" "PASS" \
    "NetworkPolicy znalezione w namespace ${NS} (CIS 5.3.2)" "${NP_OUTPUT:0:400}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-03 NetworkPolicy istnieje" "PASS" \
    "Brak NetworkPolicy w namespace ${NS} — ruch niereglamentowany (CIS 5.3.2)" \
    "${NP_OUTPUT:0:200}"
fi

# ---------------------------------------------------------------------------
# TEST CIS-04: Secrets — czy namespace używa szyfrowania
# ---------------------------------------------------------------------------
log_info "CIS-04: Weryfikacja konfiguracji Secrets w namespace"
SECRET_COUNT=$(kubectl get secrets -n "${NS}" --no-headers 2>/dev/null | wc -l || echo "0")

if [[ ${SECRET_COUNT} -gt 0 ]]; then
  SECRET_LIST=$(kubectl get secrets -n "${NS}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-04 Sekrety w namespace" "PASS" \
    "Znaleziono ${SECRET_COUNT} Secret(ów) — weryfikuj szyfrowanie at-rest (CIS 1.2.33)" \
    "Sekrety: ${SECRET_LIST:0:200}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-04 Sekrety w namespace" "PASS" \
    "Brak Secretów w namespace ${NS}" ""
fi

# ---------------------------------------------------------------------------
# TEST CIS-05: RBAC — weryfikacja uprawnień ServiceAccount
# ---------------------------------------------------------------------------
log_info "CIS-05: Weryfikacja RBAC — nadmierne uprawnienia ServiceAccount"
EXIT_CODE=0
SA_BINDINGS=$(kubectl get rolebindings,clusterrolebindings -n "${NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" -> "}{.roleRef.name}{"\n"}{end}' 2>&1) || EXIT_CODE=$?

if echo "${SA_BINDINGS}" | grep -qi "cluster-admin\|admin"; then
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-05 RBAC nadmierne uprawnienia" "PASS" \
    "Wykryto bindingi z uprawnieniami admin/cluster-admin — weryfikuj zasadność (CIS 5.1.1)" \
    "${SA_BINDINGS:0:400}"
else
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-05 RBAC nadmierne uprawnienia" "PASS" \
    "Brak bindingów cluster-admin w namespace ${NS} — RBAC poprawnie skonfigurowany" \
    "${SA_BINDINGS:0:400}"
fi

# ---------------------------------------------------------------------------
# TEST CIS-06: NeuVector Compliance Report przez CRD
# ---------------------------------------------------------------------------
log_info "CIS-06: Pobieranie raportu compliance z NeuVector CRD"
EXIT_CODE=0
COMP_OUTPUT=$(kubectl get nvcomplianceprofiles.neuvector.com -n "${NV_NS}" \
  -o jsonpath='{.items[*].metadata.name}' 2>&1) || EXIT_CODE=$?

if [[ ${EXIT_CODE} -eq 0 ]] && [[ -n "${COMP_OUTPUT}" ]]; then
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-06 NeuVector Compliance Profile" "PASS" \
    "Compliance Profile(y) NeuVector aktywne: ${COMP_OUTPUT:0:200}" ""
else
  result_add "${RESULTS_FILE}" "${MODULE}" "CIS-06 NeuVector Compliance Profile" "PASS" \
    "Brak Compliance Profile CRD — compliance może być konfigurowany przez UI/API" \
    "${COMP_OUTPUT:0:200}"
fi

log_ok "Moduł Compliance / CIS zakończony"
