# github-runners

Layered, multi-arch (amd64/arm64) container images for GitHub Actions
self-hosted runners on [ARC](https://github.com/actions/actions-runner-controller),
plus a standalone minimal TeX Live image with on-demand package installation.

```
ubuntu:24.04
├── runner-base          slim rootless runner (no docker) — ARC k8s mode,
│   │                    and the parent for specialized runners
│   ├── runner-dind      + rootless docker engine, rootlesskit, compose
│   └── runner-texlive   + TeX Live tree grafted from texlive-slim
└── texlive-slim         standalone minimal TeX Live + texbuild
```

| Image | Contents | Use |
|---|---|---|
| `runner-base` | actions/runner, container hooks, gh CLI, dumb-init, uid 1001 | ARC `kubernetes` mode; base image |
| `runner-dind` | runner-base + docker (rootless) + compose | ARC `dind` mode, image builds |
| `texlive-slim` | scheme-basic + luatex + latex/fonts-recommended + mathscience + latexmk + `texbuild` (~550 MB) | local/CI PDF builds |
| `runner-texlive` | runner-base + texlive-slim tree + `texbuild` | LaTeX CI on ARC |

## TeX Live: version-controlled, minimal, self-expanding

`texlive-slim` installs TeX Live with the upstream `install-tl` from CTAN —
not distro packages — so the version is yours to control:

- **Latest release** (default): `TL_REPO=https://mirror.ctan.org/systems/texlive/tlnet`
- **Pin a historic release**: `--build-arg TL_REPO=https://ftp.tug.org/historic/systems/texlive/2025/tlnet-final`

Docs and sources are excluded; the base is `scheme-basic` plus
`collection-luatex`, `collection-latexrecommended`, `collection-fontsrecommended`,
`collection-mathscience` (mathtools, unicode-math, siunitx, physics, …
math-heavy work never waits on installs), and `latexmk` — tunable via
`TL_SCHEME` / `TL_COLLECTIONS` / `TL_EXTRA_PACKAGES` build args. To stay slim,
`cm-super` (67MB of legacy Type1 *text* fonts for T1-encoded CM under
pdflatex — no math content; Latin Modern is its modern replacement) is pruned
after install (`TL_PRUNE_PACKAGES`), and AFM metrics are stripped. All math
fonts ship in the image: CM math, AMS symbols, Latin Modern Math, TeX Gyre
Math. Everything else installs on demand.

### texbuild

`texbuild` wraps `latexmk` (default engine **lualatex**; `--pdflatex` /
`--xelatex` supported): compile → scrape the log for missing files, fonts,
and executables → resolve them to TeX Live packages with
`tlmgr search --global --file` → install → retry, until the build converges.

```sh
# in a project directory
docker run --rm -v "$PWD":/workdir ghcr.io/OWNER/texlive-slim texbuild main.tex
docker run --rm -v "$PWD":/workdir ghcr.io/OWNER/texlive-slim texbuild --pdflatex main.tex
```

Package lists next to the target are preinstalled **before** the first
compile (discovery still runs afterward):

- `<jobname>.packages` — per-document list
- `texbuild-packages.txt` — per-project list; also where texbuild **records**
  every package it installed on demand, so run 2 starts warm. Commit it.

Bake a stabilized project's packages into your own image layer:

```dockerfile
FROM ghcr.io/OWNER/texlive-slim
COPY texbuild-packages.txt /tmp/
RUN texbuild --from-manifest /tmp/texbuild-packages.txt
```

See `texbuild --help` for all options (`--max-passes`, `--no-preinstall`,
`--manifest`, extra latexmk args after `--`).

## Using the runners with ARC

Point a scale set at an image, e.g. `values.yaml`:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/OWNER/runner-texlive:latest
        command: ["/home/runner/run.sh"]
```

For `runner-dind`, use ARC's `containerMode: type: dind` (or run rootless
dockerd yourself; `dockerd-rootless.sh` and rootlesskit are on PATH, subuid
ranges are configured for `runner`). **Rootless docker's data-root must not
sit on an overlayfs rootfs** — mount an `emptyDir` at
`/home/runner/.local/share/docker` in Kubernetes (the image's `VOLUME`
declaration covers plain `docker run`, but Kubernetes ignores `VOLUME`).

Notes:
- Runners are rootless (uid 1001, no sudo). Extend the image for tools that
  need root to install.
- In `runner-texlive` the TeX Live tree and `/usr/local/bin` are owned by
  `runner`, so `texbuild`/`tlmgr` can install packages during jobs.

## Building

Local (host arch, loaded into docker):

```sh
scripts/build.sh                    # all four, dependency-ordered
scripts/build.sh texlive-slim       # just one
./tests/smoke.sh texlive-slim:local # exercise texbuild incl. on-demand installs
```

Multi-arch push: `PUSH=1 OWNER=you scripts/build.sh`

CI — candidate → test → promote (`.github/workflows/build.yml`):

- **Native per-arch builds, no QEMU**: each image builds on `ubuntu-latest`
  (amd64) and `ubuntu-24.04-arm` (arm64) in parallel, is pushed by digest,
  and the digests are merged into one multi-arch candidate manifest,
  `:build-<run_id>` (`_build-image.yml`). arm64 hosted runners are free for
  public repos.
- **Tests gate the release**, running natively on both architectures:
  structural checks (`runner-base`), size budget + the smoke suite
  (`texlive-slim`), rootless dockerd boot + hello-world (`runner-dind`),
  and on-demand `texbuild` installs as uid 1001 (`runner-texlive`).
  A live canary test additionally registers the candidate as an ephemeral
  self-hosted runner against this repo and runs a real dispatched job on it
  (`canary.yml`) — it activates once the `RUNNER_TEST_PAT` secret exists
  (fine-grained PAT for this repo: Administration read/write + Actions
  read/write) and skips with a warning until then.
- **Promote**: only when every test passes are candidates retagged
  (manifest-only, no rebuild) to `latest`, `YYYYMMDD`, and — for runner
  images — `runner-<version>`. `latest` never moves on a failed run;
  rollback = repoint at an older date tag.
- **Weekly rebuild** (Mon 05:17 UTC): a `versions` job resolves the latest
  `actions/runner`, container hooks, docker, and compose releases at build
  time, so runner images always ship a current runner — GitHub refuses jobs
  to runners that fall too far behind. Scheduled runs build with `no-cache`
  so apt packages and the TeX Live tree are actually refreshed, not
  replayed from layer cache.

### Version pins (build args)

CI resolves the latest releases at build time; the Dockerfile defaults below
are fallbacks for local/offline builds.

| Arg | Default |
|---|---|
| `RUNNER_VERSION` | 2.336.0 |
| `RUNNER_CONTAINER_HOOKS_VERSION` | 0.8.1 |
| `DOCKER_VERSION` | 29.7.2 |
| `COMPOSE_VERSION` | v5.5.0 |
| `DUMB_INIT_VERSION` | 1.2.5 |
| `TL_REPO` | current CTAN tlnet |

**Note on TeX Live year rollover:** on-demand installs pull from `TL_REPO`.
When CTAN moves to a new TL year, `tlmgr` from an older image can no longer
install from the current mirror. The weekly scheduled rebuild handles this
automatically; for pinned setups use the matching `tlnet-final` historic URL.
