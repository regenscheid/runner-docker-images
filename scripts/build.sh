#!/usr/bin/env bash
# Local build helper. Builds images in dependency order.
#
# Usage:
#   scripts/build.sh [image...]            # host arch, load into local docker
#   PUSH=1 scripts/build.sh [image...]     # multi-arch buildx push to registry
#
# Images: runner-base runner-dind texlive-slim runner-texlive (default: all)
# In load mode every image is also tagged <name>:local, and dependent images
# build FROM the :local tags (plain `docker build`, which can see local
# images — a buildx container driver cannot).
#
# Env:
#   REGISTRY   (default ghcr.io)
#   OWNER      (default: gh username, else 'local'; lowercased)
#   TAG        (default latest)
#   PLATFORMS  (default linux/amd64,linux/arm64 — push mode only)
set -euo pipefail
cd "$(dirname "$0")/.."

REGISTRY="${REGISTRY:-ghcr.io}"
OWNER="${OWNER:-$(gh api user -q .login 2>/dev/null || echo local)}"
OWNER="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
TAG="${TAG:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-0}"

TARGETS=("$@")

img() { echo "${REGISTRY}/${OWNER}/$1:${TAG}"; }

# Parent-image reference for dependent builds
base_ref() { if [[ "$PUSH" == "1" ]]; then img "$1"; else echo "$1:local"; fi; }

want() {
  [[ ${#TARGETS[@]} -eq 0 ]] && return 0
  local t
  for t in "${TARGETS[@]}"; do
    [[ "$t" == "$1" ]] && return 0
  done
  return 1
}

build() {
  local name="$1" dockerfile="$2"; shift 2
  if [[ "$PUSH" == "1" ]]; then
    docker buildx build --platform "$PLATFORMS" --push \
      --file "$dockerfile" --tag "$(img "$name")" "$@" .
  else
    docker build \
      --file "$dockerfile" --tag "$(img "$name")" --tag "$name:local" "$@" .
  fi
}

want runner-base    && build runner-base    images/runner-base.Dockerfile
want texlive-slim   && build texlive-slim   texlive/Dockerfile
want runner-dind    && build runner-dind    images/runner-dind.Dockerfile \
                         --build-arg BASE_IMAGE="$(base_ref runner-base)"
want runner-texlive && build runner-texlive images/runner-texlive.Dockerfile \
                         --build-arg BASE_IMAGE="$(base_ref runner-base)" \
                         --build-arg TEXLIVE_IMAGE="$(base_ref texlive-slim)"
echo "Done."
