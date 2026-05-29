# Dockerfile — NeuVector Security Tester
# WAŻNE: chmod +x na wszystkich skryptach jest wykonywany tutaj podczas budowania
# obrazu. NeuVector w trybie Protect blokuje chmod w runtime.
FROM alpine:3.19

RUN apk add --no-cache \
      bash \
      curl \
      jq \
      bc \
      netcat-openbsd \
      wget \
      ca-certificates \
      openssl

# kubectl
ARG KUBECTL_VERSION=v1.29.3
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

WORKDIR /app

COPY run_tests.sh        ./
COPY lib/                ./lib/
COPY tests/              ./tests/
COPY report/             ./report/

# KLUCZOWE: wszystkie uprawnienia ustawiane przy budowie obrazu
# NeuVector blokuje chmod w trybie Protect
RUN chmod +x \
      /app/run_tests.sh \
      /app/lib/logger.sh \
      /app/lib/results.sh \
      /app/tests/01_network_policy.sh \
      /app/tests/02_dlp.sh \
      /app/tests/03_waf.sh \
      /app/tests/04_runtime_process.sh \
      /app/tests/05_vulnerability_scan.sh \
      /app/tests/06_compliance_cis.sh \
      /app/report/generate_report.sh

RUN mkdir -p /report

ENTRYPOINT ["/bin/bash", "/app/run_tests.sh"]
