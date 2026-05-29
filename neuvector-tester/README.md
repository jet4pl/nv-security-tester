# NeuVector Security Test Suite

Framework testowy do weryfikacji zabezpieczeń NeuVector w klastrze RKE2.
Uruchamiany jako Kubernetes `Job` w izolowanym namespace sandbox.

---

## Struktura projektu

```
neuvector-tester/
├── run_tests.sh              # Główny orchestrator
├── Dockerfile                # Obraz Docker z narzędziami
├── lib/
│   ├── logger.sh             # Kolorowe logowanie
│   └── results.sh            # Zapis wyników do JSON
├── tests/
│   ├── 01_network_policy.sh  # Testy segmentacji sieci
│   ├── 02_dlp.sh             # Data Loss Prevention
│   ├── 03_waf.sh             # Web Application Firewall
│   ├── 04_runtime_process.sh # Runtime Process Security
│   ├── 05_vulnerability_scan.sh # Vulnerability Scanner
│   └── 06_compliance_cis.sh  # Compliance / CIS Benchmarks
├── report/
│   └── generate_report.sh    # Generator raportu HTML
└── k8s/
    └── manifests.yaml        # Wszystkie manifesty Kubernetes
```

---

## Szybki start

### 1. Wdróż namespace i target app

```bash
kubectl apply -f k8s/manifests.yaml
```

Poczekaj aż target-app jest Running:
```bash
kubectl wait --for=condition=Ready pod -l app=target-app \
  -n neuvector-test --timeout=60s
```

### 2. Zbuduj i wypchnij obraz Docker

```bash
# Lokalne registry lub twoje registry
docker build -t nv-security-tester:latest .

# Jeśli klaster nie ma dostępu do zewnętrznego registry:
# Dla RKE2 z containerd — importuj lokalnie na każdym nodzie:
docker save nv-security-tester:latest | \
  ssh <node> sudo ctr images import -
```

### 3. Uruchom Job testowy

```bash
kubectl apply -f k8s/manifests.yaml

# Obserwuj logi na żywo:
kubectl logs -n neuvector-test \
  -l app=nv-security-tester \
  --follow
```

### 4. Pobierz raport HTML

```bash
# Poczekaj na zakończenie Job'a
kubectl wait --for=condition=Complete job/nv-security-tester \
  -n neuvector-test --timeout=600s

# Pobierz raport
POD_NAME=$(kubectl get pod -n neuvector-test \
  -l app=nv-security-tester \
  -o jsonpath='{.items[0].metadata.name}')

kubectl cp neuvector-test/${POD_NAME}:/report/report.html \
  ./neuvector_report.html

# Otwórz raport
xdg-open ./neuvector_report.html   # Linux
open ./neuvector_report.html       # macOS
```

### 5. Sprzątanie

```bash
kubectl delete namespace neuvector-test
kubectl delete clusterrole nv-tester-cluster-reader
kubectl delete clusterrolebinding nv-tester-cluster-binding
```

---

## Konfiguracja

Zmienne środowiskowe (ConfigMap `nv-test-scripts` lub bezpośrednio w Job):

| Zmienna        | Domyślna          | Opis                                     |
|----------------|-------------------|------------------------------------------|
| `NAMESPACE`    | `neuvector-test`  | Namespace sandbox                        |
| `NV_NAMESPACE` | `neuvector`       | Namespace NeuVector                      |
| `TARGET_SVC`   | `target-app`      | Nazwa serwisu docelowego                 |
| `TEST_TIMEOUT` | `60`              | Timeout na jeden moduł testowy (sekundy) |
| `REPORT_DIR`   | `/report`         | Katalog na wyniki i raport               |

---

## Statusy testów

| Status    | Znaczenie                                                    |
|-----------|--------------------------------------------------------------|
| `PASS`    | Test wykonany — atak nie zablokowany (lub test konfiguracji OK) |
| `BLOCKED` | NeuVector zablokował symulowany atak ✓                       |
| `FAIL`    | Błąd środowiskowy (brak Pod'a, błąd kubectl, itp.)          |
| `TIMEOUT` | Przekroczono limit czasu `TEST_TIMEOUT`                      |

---

## Testy per moduł

### 01 Network Policy
- `NP-01` Egress do zewnętrznego IP (8.8.8.8)
- `NP-02` Ruch cross-namespace do Kubernetes API
- `NP-03` Połączenie na niestandardowy port (9999)
- `NP-04` Dozwolony ruch wewnętrzny (baseline)

### 02 DLP
- `DLP-01` Numer karty kredytowej w HTTP POST
- `DLP-02` Numer PESEL w HTTP POST
- `DLP-03` Token API/JWT w nagłówku Authorization
- `DLP-04` Numer paszportu/SSN w body

### 03 WAF
- `WAF-01` SQL Injection (GET param)
- `WAF-02` XSS (script tag w GET)
- `WAF-03` Path Traversal (../etc/passwd)
- `WAF-04` Command Injection (POST body)
- `WAF-05` Log4Shell symulacja (nagłówek)
- `WAF-06` SSRF (cloud metadata 169.254.169.254)

### 04 Runtime Process
- `RT-01` Uruchomienie netcat w kontenerze
- `RT-02` Odczyt /etc/shadow
- `RT-03` wget do zewnętrznego hosta
- `RT-04` Zapis do /proc/sys/kernel
- `RT-05` Ustawienie bitu SUID na /bin/sh

### 05 Vulnerability Scanner
- `VS-01` Weryfikacja aktywności Scanner Pod'ów
- `VS-02` Liczba podatności CRITICAL/HIGH
- `VS-03` Adnotacje skanowania na Pod'ach
- `VS-04` Admission Webhook (blokada CVE)

### 06 Compliance / CIS
- `CIS-01` Kontenery non-root (CIS 5.2.6)
- `CIS-02` allowPrivilegeEscalation:false (CIS 5.2.5)
- `CIS-03` Istnienie NetworkPolicy (CIS 5.3.2)
- `CIS-04` Sekrety i szyfrowanie at-rest (CIS 1.2.33)
- `CIS-05` RBAC bez nadmiernych uprawnień (CIS 5.1.1)
- `CIS-06` NeuVector Compliance Profile CRD

---

## Wymagania

- Kubernetes RKE2 >= 1.27
- NeuVector >= 5.2 zainstalowany i w trybie **Protect**
- `kubectl` skonfigurowany z dostępem do klastra
- Docker do budowania obrazu
- `jq`, `bc` dostępne w obrazie (zawarte w Dockerfile)
