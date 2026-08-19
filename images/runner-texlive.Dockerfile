# runner-base + minimal TeX Live (from texlive-slim) + texbuild.
# TeX Live tree is owned by 'runner' so texbuild's on-demand tlmgr
# installs work inside CI jobs.
ARG BASE_IMAGE=ghcr.io/OWNER/runner-base:latest
ARG TEXLIVE_IMAGE=ghcr.io/OWNER/texlive-slim:latest

FROM ${TEXLIVE_IMAGE} AS texlive

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="runner-texlive" \
      org.opencontainers.image.description="Ubuntu 24.04 GitHub Actions runner with minimal TeX Live + on-demand package installation (amd64/arm64)"

USER root

# Same OS deps the texlive image relies on
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      fontconfig \
      ghostscript \
      perl \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

# TeX Live tree, bin symlinks (tlmgr set sys_bin=/usr/local/bin), texbuild,
# and the fontconfig integration file.
COPY --from=texlive --chown=runner:runner /usr/local/texlive /usr/local/texlive
COPY --from=texlive /usr/local/bin /usr/local/bin
COPY --from=texlive /etc/fonts/conf.d/09-texlive-fonts.conf /etc/fonts/conf.d/09-texlive-fonts.conf

# /usr/local/bin must stay writable by runner: tlmgr symlinks new package
# binaries there during on-demand installs.
RUN chown runner:runner /usr/local/bin && fc-cache -fs

ENV TEXBUILD_ENGINE=lualatex

USER runner

# Sanity checks as the runner user
RUN lualatex --version | head -1 && \
    pdflatex --version | head -1 && \
    latexmk --version | head -2 && \
    tlmgr --version | head -1

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
