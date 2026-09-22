# pi-roamgate-docker

A Docker Compose stack that runs [herdr](https://github.com/herdrdev/herdr)
(control plane), [pi](https://github.com/earendil-works/pi) (coding agent),
and [roamgate](https://github.com/powerfooI/roamgate) (web client for herdr)
together, sharing a Unix-socket volume — no SSH transport, no host sshd
dependency, identical behaviour on macOS Docker Desktop and native Linux.

**Hard rule:** roamgate is never executed directly on the host OS in any
form (macOS Gatekeeper blocks the bare binary). It only ever runs inside
the `roamgate` container. herdr and pi have no such restriction, but this
stack runs all three in containers for consistency.

## Architecture

Three services, one bridge network, four named volumes:

- `herdr` — runs `herdr server` in the foreground. Writes `herdr_socket`
  (the shared Unix-socket volume, rw) and `herdr_state`
  (`~/.config/herdr`). No published ports — herdr has no TCP listener.
  **herdr spawns pane child processes inside its own container's
  filesystem**, so this image carries the full toolchain (node, pi, git,
  gh, kubectl, worktrunk, bash, openssh-client) — not just the bare
  herdr binary.
- `pi` — no daemon mode exists for pi, so the container just runs
  `sleep infinity`; you attach with
  `docker compose exec -it pi pi`. Mounts `herdr_socket` read-only and
  `pi_state` (`~/.pi/agent`).
- `roamgate` — the web UI, published on `127.0.0.1:8787` by default.
  Mounts `herdr_socket` read-only and its own `roamgate_state`
  (`~/.config/herdr` inside *its own* container/home — roamgate is
  fundamentally a Herdr client sharing Herdr's config namespace, but this
  is a separate named volume from herdr's own state).

All three bind-mount the directory named by `WORKSPACE_DIR` (defaults to
`./workspace` if unset — see `.env.example`) at the identical path
`/workspace`, read-write. This matters because herdr reports absolute
paths for pane CWDs, and those paths must resolve identically in all
three containers (file preview/diff in roamgate, edits from pi) — same
absolute path, no translation needed.

`pi_state` is intentionally shared into **both** the `pi` container
(`/home/pi/.pi/agent`) and the `herdr` container
(`/home/herdr/.pi/agent`), so pane-launched pi processes (started from
roamgate, via herdr) share the same authenticated identity as the
standalone `pi` container. pi's core `auth.json`/`settings.json`/
`models.json` use cross-process file locking, making this reasonably
safe. **Do not concurrently resume the same pi session from both
containers at once** — starting fresh/different sessions from each is
fine.

`HERDR_ENV` is deliberately left **unset** in the standalone `pi`
container. It's meant to be injected by herdr into real pane child
processes along with a truthful `HERDR_PANE_ID`; the standalone container
can't supply a truthful one, so we don't fake it.

## Prerequisites

- Docker Engine + Compose v2 (`docker compose version`)
- This host's architecture: amd64 or arm64. Both are pinned and
  checksum-verified at build time (see `.env.example` for version pins),
  but **only arm64 has actually been built and run/tested** during this
  implementation (the development host is Apple Silicon/arm64). amd64's
  build-time correctness rests solely on the checksum match against
  upstream's published digests — it has not been executed or smoke-tested
  on real amd64 hardware/emulation. Treat an amd64 build as unverified at
  runtime until someone actually runs it on amd64.

## Setup

```bash
cp .env.example .env
# edit .env — at minimum set ROAMGATE_PASSWORD to a real secret
```

### WORKSPACE_DIR must exist before the first `docker compose up`

The `/workspace` bind mount uses Compose's long syntax with
`bind.create_host_path: false`, so Compose will **refuse to start** with
a clear `bind source path does not exist` error if the host directory
named by `WORKSPACE_DIR` (default `./workspace`) doesn't already exist —
it will NOT silently auto-create a root-owned directory the way Docker's
classic short bind-mount syntax does. Create it yourself first:

```bash
mkdir -p "${WORKSPACE_DIR:-./workspace}"
# On native Linux, also make sure it's owned/writable by PUID:PGID —
# see the PUID/PGID section below.
```

### PUID/PGID — read this before your first `docker compose up`

`PUID`/`PGID` are baked into all three images at **build time** (each
Dockerfile creates its user/group with those numeric ids and pre-creates
every volume mountpoint owned by them). A fresh named Docker volume
inherits the image directory's ownership when first mounted (this is
local-driver "copy-up" behavior, confirmed on both Linux and Docker
Desktop macOS for plain named volumes). This means: **no runtime chown, no
root-phase entrypoint, no setpriv, no extra capabilities — ever.**

The tradeoff: **treat `PUID`/`PGID` as fixed once you have real data in
these volumes.** Rebuilding the images after changing `PUID`/`PGID` only
fixes ownership of freshly-created mountpoints in a **new** volume — it
does nothing to already-populated `herdr_state`, `pi_state`,
`roamgate_state`, or `herdr_socket` volumes. On native Linux, it also
doesn't touch the host-owned `WORKSPACE_DIR` directory (`./workspace` by
default), which is owned by whatever host UID created it.

#### Changing PUID/PGID after first run

Option A — destroy and recreate (only acceptable for a fresh/disposable setup):

```bash
docker compose down -v
# edit .env, then:
docker compose build
docker compose up -d
```

Option B — migrate in place (preserves session state):

**Note on volume names:** Compose prefixes every named volume declared in
`compose.yaml` with the project name to get the *actual* Docker volume
name (e.g. `herdr_state` becomes `pi-roamgate_herdr_state`). This repo
pins the project name via the top-level `name: pi-roamgate` key in
`compose.yaml` specifically so this prefix can't silently drift (it would
otherwise default to the working directory's basename, which changes if
you clone/rename the checkout directory). The commands below hardcode
that resolved prefix. If you ever change `compose.yaml`'s `name:` field,
update these commands to match — or resolve the prefix dynamically with
`docker volume ls -q --filter "label=com.docker.compose.project=$(docker compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"`.

```bash
NEW_UID=1001
NEW_GID=1001

for vol in pi-roamgate_herdr_state pi-roamgate_pi_state pi-roamgate_roamgate_state pi-roamgate_herdr_socket; do
  docker run --rm -v "${vol}:/data" alpine chown -R "${NEW_UID}:${NEW_GID}" /data
done

# Compose can't reach outside itself — chown the host bind mount directly:
sudo chown -R "${NEW_UID}:${NEW_GID}" "${WORKSPACE_DIR:-./workspace}"

# then update .env and rebuild:
docker compose build
docker compose up -d
```

**Implementation note (verified empirically, not just assumed from the
plan):** the shared `herdr_socket` volume is mounted into all three
containers at the same path (`/run/herdr`). Compose creates all three
containers before starting any of them, so which image's copy of that
mountpoint "wins" the volume's one-time copy-up initialization is a
race, not something safe to rely on container/service ordering for. The
fix is *not* a runtime chown — all three Dockerfiles (`Dockerfile.herdr`,
`Dockerfile.pi`, `Dockerfile.roamgate`) now chown `/run/herdr` to the
same `PUID:PGID` at build time, so the race is moot: no matter which
image's content the volume copies up from, the ownership is identical.
This was confirmed by reproducing the failure with `docker compose up`
(volume came up `root:root 0755`) before the fix, and confirming clean
startup after adding the missing `chown` to `Dockerfile.pi` and
`Dockerfile.roamgate`.

Every entrypoint (`herdr-entrypoint.sh`, `pi-entrypoint.sh`,
`roamgate-entrypoint.sh`) checks that its state directory and
`/workspace` are writable at startup and fails loudly — printing the
observed owner/mode and pointing back to this section — if they are not.
It does not silently continue.

## Build and start

```bash
docker compose build
docker compose up -d
docker compose ps
```

## Verify

```bash
# all three healthy/running
docker compose ps

# logs
docker compose logs herdr    # expect a short banner only — normal, not a bug
docker compose logs pi
docker compose logs roamgate

# wiring
docker compose exec pi test -S /run/herdr/herdr.sock
docker compose exec pi herdr status server
docker compose exec pi gh version
docker compose exec pi kubectl version --client
docker compose exec pi pi --version
docker compose exec roamgate curl -fsS http://127.0.0.1:8787/healthz
docker compose logs roamgate | grep -E "Herdr sockets configured|Herdr reachable"
docker compose exec roamgate sh -c 'ps -eo args | grep -c "[s]sh"'   # expect 0
curl -fsS http://127.0.0.1:8787/healthz   # from host

# PTY/pane smoke test
docker compose exec pi herdr workspace list
docker compose exec pi herdr workspace create --cwd /workspace --label smoke
docker compose exec pi herdr pane split --direction right --cwd /workspace
docker compose exec pi herdr pane run --current 'echo pane-smoke-test-ok'
docker compose exec pi herdr pane read --current --source recent --lines 20

# UID coordination
for s in herdr pi roamgate; do docker compose exec "$s" id -u; done   # all identical

# security
docker compose exec pi test ! -e /var/run/docker.sock
docker compose port herdr 8787 || echo "herdr publishes nothing (expected)"
docker compose config | grep -E "host_ip|privileged|network_mode"
docker compose exec roamgate sh -c 'touch /run/herdr/x'   # must fail — it's :ro

# persistence
docker compose restart herdr && docker compose ps   # stale-socket unlink path
docker compose down && docker compose up -d          # state survives in named volumes
```

## Logs and troubleshooting

- `docker compose logs <service>` for stdout/stderr.
- If `pi` or `roamgate` fail with a socket-wait timeout, they print
  `ls -la /run/herdr`, and suggest checking `docker compose logs herdr`
  and confirming `PUID`/`PGID` match across services — the loop is
  bounded by `HERDR_WAIT_TIMEOUT` (default 60s).
- A stuck herdr socket after an unclean stop is unlinked automatically by
  `herdr-entrypoint.sh` on the next start; you should never need to
  manually remove files inside the `herdr_socket` volume.

## Backup / restore of named volumes

**Note on volume names:** as above, these are the *actual* Docker volume
names (Compose project-name-prefixed, per the pinned `name: pi-roamgate`
in `compose.yaml`), not the bare names declared under `compose.yaml`'s
`volumes:` key. Verify with `docker volume ls | grep pi-roamgate` or
`docker compose config --volumes` (which prints the bare names Compose
will prefix) before running these against a real environment.

```bash
# backup
for vol in pi-roamgate_herdr_state pi-roamgate_pi_state pi-roamgate_roamgate_state; do
  docker run --rm -v "${vol}:/data" -v "$(pwd):/backup" alpine \
    tar -C /data -czf "/backup/${vol}.tar.gz" .
done

# restore (into a fresh volume)
for vol in pi-roamgate_herdr_state pi-roamgate_pi_state pi-roamgate_roamgate_state; do
  docker volume create "${vol}"
  docker run --rm -v "${vol}:/data" -v "$(pwd):/backup" alpine \
    tar -C /data -xzf "/backup/${vol}.tar.gz"
done
```

`herdr_socket` is not meaningfully backup-worthy — it only ever holds
live socket files.

## Threat model

- No SSH keys, no host sshd. Transport is a shared Unix-socket named
  volume, mounted rw only by `herdr`, ro by `pi`/`roamgate`.
- `roamgate` is the only service with a published port, and only on
  `ROAMGATE_BIND_ADDRESS` (default `127.0.0.1`, loopback-only). It binds
  `0.0.0.0` *inside* the container (required for Docker's port forwarding
  to reach it) but that internal bind is why `ROAMGATE_PASSWORD` is
  mandatory — auth is not optional once you bind non-loopback.
- All three services run `cap_drop: [ALL]` + `security_opt:
  no-new-privileges:true`, as non-root numeric users baked in at build
  time. No `privileged`, no `network_mode: host`, no extra capabilities.
- `/workspace` is the only writable path shared across all three
  containers — treat it as the trust boundary. There is no dormant SSH
  escape hatch in this stack; `HERDR_SSH_HOST` is actively rejected by
  the `pi` and `roamgate` entrypoints (exit 1 if it's set).

## Known limitations

- **gh/kubectl credentials are deliberately deferred.** The `gh` and
  `kubectl` binaries are installed (pinned, checksum-verified) in both
  the `pi` and `herdr` images, but no credential injection (GitHub
  token, kubeconfig, Compose secrets, RBAC) is wired up in this pass. See
  the inert comment block in `docker/pi-entrypoint.sh` and
  `secrets/.gitkeep` — adding this later should be additive only.
- **Workspace-only scope.** Everything these containers can touch is
  bounded to `/workspace` (plus each service's own state volume). There
  is intentionally no SSH-based escape hatch to reach paths outside the
  bind mount, unlike some herdr/roamgate deployments that use
  `HERDR_SSH_HOST`.
- **PUID/PGID changes require manual migration** once volumes have real
  data — see "Changing PUID/PGID after first run" above. This is a
  property of baking ownership in at build time, not a bug.
- **No SBOM / full dependency license inventory.** See NOTICE — herdr
  and pi both have their own transitive dependency license surfaces that
  have not been fully inventoried; do this before any registry
  publication of these images.
- amd64 and arm64 are both pinned and checksum-verified for herdr and
  roamgate binaries (independently verified against upstream `.sha256`
  sidecars / asset digests during this implementation). `gh` and
  `kubectl` verify against their own release-provided checksum files at
  build time rather than a hardcoded digest in this repo, since both
  projects publish trustworthy per-release checksum files over HTTPS.
  **This checksum verification was done for both architectures, but only
  arm64 was actually built and run/tested** on this (Apple Silicon) host
  — amd64's correctness at runtime rests on the checksum match alone, not
  on an executed smoke test. Do not read "checksum-verified" as
  "validated equivalently on both architectures."

## Shared toolchain rationale

`herdr` and `pi` are built `FROM node:22-bookworm-slim` and install an
identical toolchain (`docker/lib/install-toolchain.sh`) plus the `pi` npm
package (`docker/lib/install-pi.sh`), the `herdr` binary
(`docker/lib/install-herdr.sh`), and `worktrunk`/`wt`
(`docker/lib/install-worktrunk.sh`, a static musl binary, portable
regardless of the base image's libc). This is intentional duplication,
not an oversight: herdr spawns pane child processes inside *its own*
container, so panes started from roamgate need
`pi`/`git`/`gh`/`kubectl`/`wt` available in the `herdr` image too, or the
stack is wired but useless. Docker's layer
cache de-duplicates identical layers on disk, so "two full images" is
mostly a disk-usage non-issue, not a real cost. `herdr` and `pi` remain
separate containers/services — separate lifecycle/failure domains is
correct even though they share a toolchain.

## Licensing

See `LICENSE` (this repo's own packaging work, MIT) and `NOTICE`
(third-party attributions for herdr, roamgate, pi, gh, kubectl, and
worktrunk).
