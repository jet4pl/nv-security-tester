# Dockerfile — NeuVector Security Tester
# Obraz zawiera wszystkie narzędzia potrzebne do testów:
# bash, curl, kubectl, jq, bc

FROM alpine:3.19

# Instalacja narzędzi
RUN apk add --no-cache \
      bash \
      curl \
      jq \
      bc \
      netcat-openbsd \
      wget \
      ca-certificates \
      openssl

# Instalacja kubectl
ARG KUBECTL_VERSION=v1.29.3
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

WORKDIR /app

# Kopiuj framework testowy
COPY run_tests.sh        ./
COPY lib/                ./lib/
COPY tests/              ./tests/
COPY report/             ./report/

# Uprawnienia wykonywania
RUN chmod +x run_tests.sh \
      lib/*.sh \
      tests/*.sh \
      report/generate_report.sh

# Katalog na wyniki raportu
RUN mkdir -p /report

# Punkt wejścia
ENTRYPOINT ["/bin/bash", "/app/run_tests.sh"]
