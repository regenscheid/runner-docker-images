# runner-base + rootless Docker (dind) + compose.
# For ARC "dind" container mode or standalone runners that build images.
ARG BASE_IMAGE=ghcr.io/OWNER/runner-base:latest
FROM ${BASE_IMAGE}

ARG DOCKER_VERSION=29.7.2
ARG COMPOSE_VERSION=v5.5.0
ARG TARGETPLATFORM

LABEL org.opencontainers.image.title="runner-dind" \
      org.opencontainers.image.description="Rootless Ubuntu 24.04 GitHub Actions runner with docker-in-docker (amd64/arm64)"

USER root

# Rootless docker prerequisites
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      dbus-user-session \
      fuse-overlayfs \
      iproute2 \
      iptables \
      kmod \
      pigz \
      uidmap \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

# Static docker engine + cli, rootless extras, compose plugin
RUN ARCH=$(echo "${TARGETPLATFORM}" | cut -d/ -f2) && \
    if [ "$ARCH" = "arm64" ]; then DL_ARCH=aarch64; else DL_ARCH=x86_64; fi && \
    curl -fLo docker.tgz \
      "https://download.docker.com/linux/static/stable/${DL_ARCH}/docker-${DOCKER_VERSION}.tgz" && \
    tar xzf docker.tgz && \
    install -o root -g root -m 755 docker/* /usr/bin/ && \
    rm -rf docker docker.tgz && \
    curl -fLo rootless.tgz \
      "https://download.docker.com/linux/static/stable/${DL_ARCH}/docker-rootless-extras-${DOCKER_VERSION}.tgz" && \
    tar xzf rootless.tgz && \
    install -o root -g root -m 755 docker-rootless-extras/* /usr/bin/ && \
    rm -rf docker-rootless-extras rootless.tgz && \
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -fLo /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${DL_ARCH}" && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
    ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Subordinate uid/gid ranges for rootless dockerd
RUN echo "runner:100000:65536" >> /etc/subuid && \
    echo "runner:100000:65536" >> /etc/subgid

ENV DOCKER_HOST=unix:///run/user/1001/docker.sock \
    SKIP_IPTABLES=1

# Rootless docker's data-root must not live on an overlayfs rootfs
# (overlay-on-overlay is rejected by the kernel, and docker 29's containerd
# image store does not fall back to fuse-overlayfs). The anonymous volume
# covers plain `docker run`; Kubernetes ignores VOLUME, so ARC deployments
# running rootless dockerd must mount an emptyDir at this path.
# The directory must pre-exist runner-owned, or the anonymous volume is
# created root-owned and rootless dockerd cannot use it.
RUN mkdir -p /home/runner/.local/share/docker && \
    chown -R runner:runner /home/runner/.local
VOLUME /home/runner/.local/share/docker

USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
