# Slim, rootless Ubuntu 24.04 runner image for GitHub Actions / ARC.
# No Docker — use runner-dind for docker-in-docker workloads, or extend
# this image for specialized runners (see runner-texlive.Dockerfile).
#
# Patterned after https://github.com/some-natalie/kubernoodles
FROM ubuntu:24.04

# Renovate-friendly version pins
ARG RUNNER_VERSION=2.336.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.8.1
ARG DUMB_INIT_VERSION=1.2.5

ARG TARGETPLATFORM

LABEL org.opencontainers.image.title="runner-base" \
      org.opencontainers.image.description="Slim rootless Ubuntu 24.04 GitHub Actions runner for ARC (amd64/arm64)" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 \
    ImageOS=ubuntu24 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base tooling commonly assumed by actions and workflows.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      git-lfs \
      gnupg \
      jq \
      locales \
      openssl \
      tar \
      time \
      tzdata \
      unzip \
      wget \
      xz-utils \
      zip \
      zstd \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

# GitHub CLI
COPY images/software/gh-cli.sh /tmp/gh-cli.sh
RUN bash /tmp/gh-cli.sh && rm /tmp/gh-cli.sh

# Runner user (uid 1001; ubuntu:24.04 ships 'ubuntu' at 1000)
RUN adduser --disabled-password --gecos "" --uid 1001 runner

WORKDIR /home/runner

# actions/runner (amd64 is published as x64)
RUN ARCH=$(echo "${TARGETPLATFORM}" | cut -d/ -f2) && \
    if [ "$ARCH" = "amd64" ]; then ARCH=x64; fi && \
    curl -fLo runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz" && \
    tar xzf runner.tar.gz && rm runner.tar.gz && \
    ./bin/installdependencies.sh && \
    rm -rf /var/lib/apt/lists/* && apt-get clean

# Container hooks for ARC "kubernetes" container mode
RUN curl -fLo hooks.zip \
      "https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip" && \
    unzip hooks.zip -d ./k8s && rm hooks.zip

# dumb-init as PID 1
RUN ARCH=$(echo "${TARGETPLATFORM}" | cut -d/ -f2) && \
    if [ "$ARCH" = "arm64" ]; then ARCH=aarch64; else ARCH=x86_64; fi && \
    curl -fLo /usr/local/bin/dumb-init \
      "https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_${ARCH}" && \
    chmod +x /usr/local/bin/dumb-init

# Rootless runtime directories
RUN mkdir -p /run/user/1001 && \
    chown runner:runner /run/user/1001 && chmod a+x /run/user/1001 && \
    mkdir -p /home/runner/externals && \
    chown -R runner:runner /home/runner

ENV HOME=/home/runner \
    PATH="/home/runner/.local/bin:${PATH}" \
    XDG_RUNTIME_DIR=/run/user/1001

USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
# ARC's scale-set spec supplies the command, typically:
#   command: ["/home/runner/run.sh"]
