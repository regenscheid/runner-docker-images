# Minimal TeX Live image, installed from upstream CTAN (install-tl).
#
# - Version-controlled: TL_REPO defaults to the current CTAN tlnet release.
#   Pin a historic release by overriding, e.g.:
#     --build-arg TL_REPO=https://ftp.tug.org/historic/systems/texlive/2025/tlnet-final
# - Small on purpose: scheme-basic + LuaLaTeX + recommended LaTeX/fonts,
#   no docs, no sources. The `texbuild` wrapper installs anything else
#   on demand via tlmgr at runtime.
# - Defaults to lualatex; pdflatex fully supported.
FROM ubuntu:24.04

ARG TARGETPLATFORM

# TeX Live repository (tlnet). Default = current release via CTAN mirror.
ARG TL_REPO=https://mirror.ctan.org/systems/texlive/tlnet
# Installation scheme; scheme-basic = plain + latex essentials (~180MB).
ARG TL_SCHEME=basic
# Extra collections layered on top of the scheme.
ARG TL_COLLECTIONS="collection-luatex collection-latexrecommended collection-fontsrecommended collection-mathscience"
# Extra individual packages.
ARG TL_EXTRA_PACKAGES="latexmk"
# Packages pruned after install to stay slim. cm-super (67MB of Type1
# fonts) only benefits legacy T1-encoded CM under pdflatex; Latin Modern
# (kept) is its modern replacement. Re-add via texbuild-packages.txt if a
# project needs it.
ARG TL_PRUNE_PACKAGES="cm-super tipa"
# Install documentation / source files (yes|no) — keep "no" to stay slim.
ARG TL_DOCFILES=no
ARG TL_SRCFILES=no

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    TEXLIVE_INSTALL_NO_CONTEXT_CACHE=1 \
    NOPERLDOC=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OS dependencies:
#   perl              - required by tlmgr / installer
#   fontconfig        - system font discovery (lualatex/luaotfload, xelatex)
#   ghostscript       - eps/pdf conversion (epstopdf and friends)
#   curl, ca-certs    - fetching installer + tlmgr over https
RUN apt-get update && \
    apt-get install -qy --no-install-recommends \
      ca-certificates \
      curl \
      fontconfig \
      ghostscript \
      perl \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

WORKDIR /tmp/install-tl

# Install TeX Live from the selected repository with a generated profile.
RUN echo "Installing TeX Live from: ${TL_REPO}" && \
    # mirror.ctan.org can redirect to a broken mirror (bad TLS cert, 404);
    # retry the installer download too - each attempt re-rolls the redirect
    ok=0 && \
    for i in 1 2 3 4 5; do \
      if curl -fsSL --connect-timeout 30 "${TL_REPO}/install-tl-unx.tar.gz" -o /tmp/installer.tar.gz; then ok=1; break; fi; \
      echo "installer download attempt $i failed; retrying in 10s"; sleep 10; \
    done && \
    [ "$ok" = 1 ] && \
    tar xzf /tmp/installer.tar.gz --strip-components=1 && rm /tmp/installer.tar.gz && \
    { \
      echo "selected_scheme scheme-${TL_SCHEME}"; \
      for c in ${TL_COLLECTIONS}; do echo "$c 1"; done; \
      if [ "${TL_DOCFILES}" = "no" ]; then echo "tlpdbopt_install_docfiles 0"; fi; \
      if [ "${TL_SRCFILES}" = "no" ]; then echo "tlpdbopt_install_srcfiles 0"; fi; \
      echo "tlpdbopt_autobackup 0"; \
      echo "tlpdbopt_sys_bin /usr/local/bin"; \
      echo "instopt_adjustpath 1"; \
      echo "instopt_letter 0"; \
    } > install.profile && \
    cat install.profile && \
    # mirror.ctan.org round-robins and individual mirrors are sometimes
    # broken mid-install; retry (each attempt re-resolves the redirect)
    ok=0 && \
    for i in 1 2 3; do \
      if perl ./install-tl --repository "${TL_REPO}" -profile install.profile; then ok=1; break; fi; \
      echo "install-tl attempt $i failed; retrying in 15s"; sleep 15; \
    done && \
    [ "$ok" = 1 ] && \
    cd / && rm -rf /tmp/install-tl

# Extra packages, pinned tlmgr repo, font caches.
RUN if [ -n "${TL_EXTRA_PACKAGES}" ]; then tlmgr install ${TL_EXTRA_PACKAGES}; fi && \
    # instopt_adjustpath only links binaries present at install-tl time;
    # re-link so packages installed just now (latexmk) land in sys_bin
    tlmgr path add && \
    if [ -n "${TL_PRUNE_PACKAGES}" ]; then tlmgr remove --force ${TL_PRUNE_PACKAGES}; fi && \
    # AFM metrics are only used when (re)installing Type1 fonts, never at
    # compile time - 43MB of dead weight in a build image
    rm -rf /usr/local/texlive/*/texmf-dist/fonts/afm && \
    # some packages ship doc/source as runfiles despite docfiles/srcfiles=0
    rm -rf /usr/local/texlive/*/texmf-dist/doc /usr/local/texlive/*/texmf-dist/source && \
    mktexlsr && \
    # keep tlmgr pointed at the same repo the image was built from, so
    # on-demand installs stay consistent with the installed release
    tlmgr option repository "${TL_REPO}" && \
    # fontconfig integration: make TL fonts visible to the system.
    # Upstream generates texlive-fontconfig.conf only via the xetex
    # package's postaction, which this install set does not include, so
    # write the equivalent fragment ourselves (fontconfig <dir> entries
    # don't glob, so resolve the year directory in the shell).
    TLROOT="$(ls -d /usr/local/texlive/[0-9]*)" && \
    printf '%s\n' \
      '<?xml version="1.0"?>' \
      '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">' \
      '<fontconfig>' \
      "<dir>${TLROOT}/texmf-dist/fonts/opentype</dir>" \
      "<dir>${TLROOT}/texmf-dist/fonts/truetype</dir>" \
      "<dir>${TLROOT}/texmf-dist/fonts/type1</dir>" \
      '</fontconfig>' \
      > /etc/fonts/conf.d/09-texlive-fonts.conf && \
    fc-cache -fs && \
    # pre-generate the luaotfload font name database for lualatex
    (luaotfload-tool -u || true)

# The on-demand build wrapper.
COPY texlive/bin/texbuild /usr/local/bin/texbuild
RUN chmod 0755 /usr/local/bin/texbuild

# Default engine for texbuild (lualatex|pdflatex|xelatex).
ENV TEXBUILD_ENGINE=lualatex

# Sanity checks.
RUN lualatex --version | head -1 && \
    pdflatex --version | head -1 && \
    latexmk --version | head -2 && \
    tlmgr --version | head -1 && \
    texbuild --help >/dev/null

WORKDIR /workdir
CMD ["bash"]
