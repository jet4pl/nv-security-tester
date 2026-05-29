# NeuVector Security Tester

Framework testowy do weryfikacji skuteczności zabezpieczeń **NeuVector** w klastrze Kubernetes RKE2. Uruchamiany jako Kubernetes `Job` w izolowanym namespace sandbox. Wyniki testów wyświetlane są w logach Pod'a jako raport Markdown — bez potrzeby pobierania plików.

---

## Spis treści

- [Wymagania](#wymagania)
- [Pobranie repozytorium](#pobranie-repozytorium)
- [Co testuje framework](#co-testuje-framework)
- [Moduły testowe](#moduły-testowe)
- [Uruchomienie testów](#uruchomienie-testów)
- [Odczyt wyników](#odczyt-wyników)
- [Statusy testów](#statusy-testów)
- [Struktura projektu](#struktura-projektu)

---

## Wymagania

- Kubernetes RKE2 >= 1.27
- NeuVector >= 5.2 zainstalowany i skonfigurowany w trybie **Protect**
- `kubectl` skonfigurowany z dostępem do klastra
- Dostęp do Docker Hub (obraz jest gotowy — nie trzeba go budować)

---

## Pobranie repozytorium

```bash
git clone https://github.com/jet4pl/nv-security-tester.git
cd nv-security-tester
```

---

## Co testuje framework

Framework symuluje rzeczywiste ataki i próby naruszenia bezpieczeństwa w klastrze Kubernetes, a następnie weryfikuje czy NeuVector je zablokował. Wszystkie testy używają **bezpiecznych payloadów** (symulacje, nie rzeczywiste exploity) — środowisko produkcyjne nie jest zagrożone.

Testy obejmują 6 modułów bezpieczeństwa NeuVector, łącznie **25 przypadków testowych**:

- segmentację sieci i polityki ruchu
- wykrywanie wycieku danych wrażliwych (DLP)
- ochronę aplikacji webowych przed typowymi atakami (WAF)
- bezpieczeństwo procesów w czasie wykonania (Runtime)
- skaner podatności CVE
- zgodność z benchmarkiem CIS Kubernetes

### Architektura nieblokująca

Każdy moduł uruchamiany jest w izolowanej podpowłoce z własnym limitem czasu. Jeśli NeuVector zablokuje (SIGKILL) któryś z testów, framework rejestruje wynik `BLOCKED` i przechodzi do kolejnego modułu — żaden pojedynczy test nie zatrzymuje całego runnera.

---

## Moduły testowe

### 01 — Network Policy (segmentacja sieci)

Weryfikuje czy NeuVector blokuje niedozwolony ruch sieciowy.

| Test | Opis |
|------|------|
| NP-01 | Ruch wychodzący (egress) do zewnętrznego IP 8.8.8.8 |
| NP-02 | Ruch cross-namespace do Kubernetes API Server |
| NP-03 | Połączenie na niestandardowy port (9999) |
| NP-04 | Dozwolony ruch wewnętrzny — test bazowy (baseline) |

### 02 — DLP (Data Loss Prevention)

Sprawdza czy NeuVector wykrywa i blokuje transmisję wrażliwych danych w ruchu HTTP.

| Test | Opis |
|------|------|
| DLP-01 | Numer karty kredytowej w POST body |
| DLP-02 | Numer PESEL w POST body |
| DLP-03 | Token API / JWT w nagłówku Authorization |
| DLP-04 | Numer paszportu i SSN w body |

### 03 — WAF (Web Application Firewall)

Symuluje typowe ataki webowe i weryfikuje reakcję WAF NeuVector.

| Test | Opis |
|------|------|
| WAF-01 | SQL Injection w parametrze GET |
| WAF-02 | Cross-Site Scripting (XSS) — tag `<script>` |
| WAF-03 | Path Traversal (`../../../etc/passwd`) |
| WAF-04 | Command Injection w POST body |
| WAF-05 | Log4Shell CVE-2021-44228 — symulacja payloadu w nagłówku |
| WAF-06 | SSRF — próba dostępu do cloud metadata (169.254.169.254) |

### 04 — Runtime Process Security

Testuje czy NeuVector blokuje niedozwolone operacje i procesy wewnątrz kontenerów.

| Test | Opis |
|------|------|
| RT-01 | Uruchomienie netcat (`nc`) w kontenerze |
| RT-02 | Odczyt pliku `/etc/shadow` |
| RT-03 | Wywołanie `wget` do zewnętrznego hosta |
| RT-04 | Próba zapisu do `/proc/sys/kernel` |
| RT-05 | Ustawienie bitu SUID na `/bin/sh` |

### 05 — Vulnerability Scanner

Weryfikuje działanie skanera podatności NeuVector — nie generuje nowych podatności, odczytuje i analizuje wyniki skanowania klastra.

| Test | Opis |
|------|------|
| VS-01 | Sprawdzenie czy Scanner Pod'y są aktywne |
| VS-02 | Liczba wykrytych podatności CRITICAL i HIGH |
| VS-03 | Adnotacje skanowania na Pod'ach |
| VS-04 | Admission Webhook — blokowanie obrazów z CVE CRITICAL |

### 06 — Compliance / CIS Benchmarks

Weryfikuje konfigurację klastra pod kątem standardów **CIS Kubernetes Benchmark**.

| Test | Opis |
|------|------|
| CIS-01 | Kontenery działające jako non-root (CIS 5.2.6) |
| CIS-02 | `allowPrivilegeEscalation: false` (CIS 5.2.5) |
| CIS-03 | Istnienie NetworkPolicy w namespace (CIS 5.3.2) |
| CIS-04 | Sekrety i szyfrowanie at-rest (CIS 1.2.33) |
| CIS-05 | RBAC bez nadmiernych uprawnień (CIS 5.1.1) |
| CIS-06 | NeuVector Compliance Profile CRD |

---

## Uruchomienie testów

### Krok 1 — Wdróż namespace, target app, RBAC i uruchom test

```bash
kubectl apply -f k8s/manifests.yaml
```

Poczekaj aż aplikacja docelowa jest gotowa:

```bash
kubectl wait --for=condition=Ready pod \
  -l app=target-app \
  -n neuvector-test \
  --timeout=60s
```

Obserwuj postęp testów na żywo:

```bash
kubectl logs -n neuvector-test \
  -l app=nv-security-tester \
  --follow
```

---

## Odczyt wyników

Po zakończeniu Job'a raport Markdown jest dostępny w logach Pod'a.

### Pełne logi z raportem

```bash
POD=$(kubectl get pod -n neuvector-test \
  -l app=nv-security-tester \
  -o jsonpath='{.items[0].metadata.name}')

kubectl logs -n neuvector-test "${POD}"
```

### Samo podsumowanie (tabela wyników)

```bash
kubectl logs -n neuvector-test "${POD}" \
  | grep -A 9999 "NEUVECTOR SECURITY TEST REPORT"
```

### Plik CSV z surowymi wynikami

```bash
kubectl cp neuvector-test/${POD}:/report/results.csv ./neuvector_results.csv
```

Format CSV: `STATUS|MODULE|TEST|OPIS|TIMESTAMP`

### Krok 2 Sprzątanie po testach

```bash
kubectl delete namespace neuvector-test
kubectl delete clusterrole nv-tester-cluster-reader
kubectl delete clusterrolebinding nv-tester-cluster-binding
```

---

## Statusy testów

| Status | Znaczenie |
|--------|-----------|
| `BLOCKED` | NeuVector wykrył i zablokował symulowany atak ✓ |
| `PASS` | Atak nie został zablokowany — wymaga weryfikacji polityk |
| `FAIL` | Błąd środowiskowy (brak Pod'a, błąd kubectl itp.) |
| `TIMEOUT` | Moduł przekroczył limit czasu |

W środowisku z prawidłowo skonfigurowanym NeuVector w trybie **Protect** oczekiwany wynik to `BLOCKED` dla wszystkich testów atakujących. Status `PASS` oznacza, że dana reguła może wymagać konfiguracji.

---

## Struktura projektu

```
nv-security-tester/
├── run_tests.sh                 # Główny orchestrator
├── Dockerfile                   # Obraz Alpine z bash/curl/kubectl
├── k8s/
│   └── manifests.yaml           # Namespace, target-app, RBAC, Job
├── lib/
│   ├── logger.sh                # Kolorowe logowanie
│   └── results.sh               # Zapis wyników (CSV, bez zewnętrznych narzędzi)
├── tests/
│   ├── 01_network_policy.sh
│   ├── 02_dlp.sh
│   ├── 03_waf.sh
│   ├── 04_runtime_process.sh
│   ├── 05_vulnerability_scan.sh
│   └── 06_compliance_cis.sh
└── report/
    └── generate_report.sh       # Generator raportu (legacy)
```

---

## Konfiguracja

Zmienne środowiskowe dostępne przez ConfigMap `nv-test-scripts` w `k8s/manifests.yaml`:

| Zmienna | Domyślna | Opis |
|---------|----------|------|
| `NAMESPACE` | `neuvector-test` | Namespace sandbox testów |
| `NV_NAMESPACE` | `neuvector` | Namespace gdzie działa NeuVector |
| `TARGET_SVC` | `target-app` | Nazwa serwisu docelowego |
| `TEST_TIMEOUT` | `90` | Maksymalny czas jednego modułu (sekundy) |

---

## Licencja

GPL v3

