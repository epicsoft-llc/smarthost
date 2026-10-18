# AGENTS.md

Guidance for AI coding agents and contributors working in this repository.

## What this is

A single-purpose Docker image: Alpine + Postfix configured as an outbound SMTP relay
(smarthost). There is no application code — the product is three files: `Dockerfile`,
`smarthost.sh` (entrypoint) and `.gitlab-ci.yml`; `test/` holds the test environment.
`README.md` is the published Docker Hub description and is uploaded by the pipeline, so it
is part of the release artifact, not just documentation.

| | |
|---|---|
| **Repository** | developed on `gitlab.com/epicsoft-networks/smarthost` (branches `develop` and `master`), mirrored to `github.com/epicsoft-llc/smarthost` |
| **Registries** | `registry.gitlab.com/epicsoft-networks/smarthost` and Docker Hub `epicsoft/smarthost` |
| **Platforms** | `linux/amd64` and `linux/arm64` |

## Architecture

Configuration flows in one direction, ENV → Postfix, at container start:

1. `Dockerfile` declares every `SMARTHOST_*` variable with its default (empty for the
   required ones).
2. `smarthost.sh` validates the variables (each missing one exits with its own code,
   `101`–`108`), then translates them into `postconf -e` calls against
   `/etc/postfix/main.cf`, plus two generated map files: `/etc/postfix/sasl_passwd`
   (relay credentials) and `/etc/postfix/header_check` (only when `SMARTHOST_FORCE_FROM`
   is set).
3. The script `exec`s `postfix -c /etc/postfix start-fg`, so Postfix runs in the
   foreground as PID 1 and `maillog_file=/dev/stdout` sends the mail log to the
   container log.

Nothing is persisted — the container is reconfigured from scratch on every start.

### Conventions to keep when changing behaviour

- **A new environment variable must be added in three places**, or it will be silently
  broken: `ENV` in `Dockerfile`, handling in `smarthost.sh`, and the "Environment
  variables" list in `README.md` (uploaded to Docker Hub by CI, so it is the published
  documentation).
- **Validation vs. optional**: variables that have a non-empty default in the Dockerfile
  are still validated as non-empty in `smarthost.sh`, so a user who blanks them gets a
  clear failure. Genuinely optional variables (`SMARTHOST_FORCE_FROM`,
  `SMARTHOST_INIT_ALIAS_DATABASE`, `TZ`) are not validated. New required variables take
  the next free exit code after `109`.
- **Booleans** are parsed loosely by convention:
  `grep -i -E "(y|yes|true|1)"` — keep that form for new flags.
- **Quote every `postconf -e` argument.** An unquoted expansion is word-split and
  `postconf` aborts with `missing '=' after attribute name` — a `SMARTHOST_NETWORKS`
  value written with a space after the comma used to kill the container this way.
- **Map type is `lmdb`** (`smtp_sasl_password_maps=lmdb:/etc/postfix/sasl_passwd`);
  Alpine's Postfix has no Berkeley DB. Related: `newaliases` is run at start
  (`SMARTHOST_INIT_ALIAS_DATABASE`) because Postfix otherwise fails on a missing
  `/etc/postfix/aliases.lmdb`.
- **`sasl_passwd` is `640 root:postfix`**, not `600`. It holds the relay password in clear
  text, but `smtp(8)` runs as `mail_owner` (`postfix`) and opens the map itself, so
  root-only `600` fails at delivery time with
  `open database /etc/postfix/sasl_passwd.lmdb: Permission denied`.
- **Values are rejected if they span more than one line** (exit `109`). Both generated map
  files are built with `echo`, so a second line becomes a second map entry: further
  `header_checks` rules, or credentials for another relay host.
- **`$` in `SMARTHOST_FORCE_FROM` is doubled to `$$`.** In a regexp map replacement a `$`
  starts a back-reference, and the pattern has no capture group. Unescaped it does not
  fail the start - postfix drops the rule at delivery time and the mail leaves with its
  original `From` and `status=sent`.
- **`regexp:` maps are never `postmap`ed.** `smtp_header_checks` reads
  `/etc/postfix/header_check` as plain text; compiling it only produces an unused `.lmdb`
  in which postmap lowercases the pattern. Only `sasl_passwd` gets a `postmap`.
- **Port 465 is a special case**: it forces `smtp_tls_wrappermode=yes` and
  `smtp_tls_security_level=encrypt`, overriding `SMARTHOST_TLS_SECURITY_LEVEL`. This
  override runs after the generic TLS block — order matters.

## Build and test

```bash
# build (ALPINE_VERSION selects the base image, default latest)
docker build -t smarthost:dev .

# the smoke tests CI runs before every push
docker run --rm smarthost:dev postconf mail_version
docker run --rm -e SMARTHOST_HOST= smarthost:dev; echo $?     # -> 101

# run it; expect the banner, "Configuration success", then Postfix's foreground log
docker run --rm -it -p 1025:25 \
  -e SMARTHOST_HOST=mail.example.com \
  -e SMARTHOST_PORT=465 \
  -e SMARTHOST_USER=info@example.com \
  -e SMARTHOST_PASSWORD=secret \
  -e SMARTHOST_DOMAIN=example.com \
  smarthost:dev
```

`test/test.sh` is the local test environment, container-only: the relay, an SMTP sink it
delivers to and the clients that submit mail all run in containers; only the logs under
`test/.logs/` (git-ignored) reach the host. Called without an argument it prints its help.

```bash
bash test/test.sh all                # every group ('default' is an alias for it)
bash test/test.sh relay tls          # only these groups
bash test/test.sh --keep relay       # leave the containers up afterwards
bash test/test.sh --list             # the group names
bash test/clean.sh env               # remove leftovers of an interrupted run
```

The groups: `validation` (configuration rejected before Postfix starts), `injection` (a
value over two lines is refused), `config` (the environment becomes `main.cf`), `quoting`,
`credentials` (the password map is written, readable for Postfix, private otherwise),
`headers`, `tls`, `relay` (a mail really goes through, and only from a trusted client) and
`lifecycle`. Everything the tests create carries the docker label `smarthost-test`, which
is how `clean.sh` cleans up without knowing what ran.

## Tags

| Tags | Built from | Content |
|---|---|---|
| `latest` | branch `master` (push, weekly schedule) and every release | `alpine:latest` with the newest packages |
| `develop` | branch `develop` | GitLab registry only, not for production |
| `X.Y.Z`, `X.Y`, `X` | a git tag `X.Y.Z` | frozen at release time — the tags a deployment should pin |

A release also moves `latest`. Versioning follows Semantic Versioning; the rules are at the
top of `CHANGELOG.md`.

## Pipeline structure (`.gitlab-ci.yml`)

| Job | Trigger | Action |
|---|---|---|
| `develop` | branch `develop` | build and test every platform, push `develop` to the GitLab registry |
| `latest` | branch `master` (push, weekly schedule) | the same, pushes `latest` to both registries |
| `release` | tag `X.Y.Z` | fails unless `CHANGELOG.md` has `## [X.Y.Z] - <date>`; same build, pushes `X.Y.Z`, `X.Y`, `X` and `latest` to both registries |
| `uploadReadme` | branch `master` | README as Docker Hub description, at most 25,000 bytes |
| `github-release` | tag `X.Y.Z`, after `release` | waits for the tag on GitHub, creates the release from the `CHANGELOG.md` entry |

Every platform is built on its own, loaded and smoke-tested **before** the multi-platform
push, which reuses those layers from the build cache — a broken image never reaches a
registry. The working branch is `develop`; `master` is the release branch.

- **`default: tags: [imagex]`** pins the pipeline to a runner host with QEMU binfmt
  handlers registered. The images install prebuilt distro packages, so the non-native half
  is built under emulation, and the handlers are host-wide kernel state that CI cannot set
  up. Without them the arm64 half dies with `exec /bin/sh: exec format error`; the
  `docker buildx inspect --bootstrap` line at the top of each build shows whether
  `linux/arm64` is listed.
- **`BUILD_PLATFORMS`** is the single place the platform list is defined.
- **`BUILDX_NO_DEFAULT_ATTESTATIONS: "1"`** keeps buildx from attaching provenance/SBOM
  attestations. Not cosmetic: with them the GitLab registry rejects the push with
  `unknown: blob unknown to registry - sha256:…` naming the image manifest, and they also
  show up as `unknown/unknown` entries on the Docker Hub tag page.
- The build uses the **built-in `default` builder**. Do not reintroduce a
  `docker-container` builder (`docker context create` + `docker buildx create`) — that was
  the previous setup and is what the attestation push failure surfaced under.

CI variables: `DOCKER_HUB_USER`, `DOCKER_HUB_TOKEN`, `GITHUB_TOKEN` (masked, protected — so
the tags must be protected (`*.*.*`) or the jobs see no token). The tokens go in over stdin
and through the environment, never onto a command line.

**GitHub mirror:** a push mirror in the GitLab project settings (Repository → Mirroring
repositories) with its own token — not part of the pipeline. `GITHUB_TOKEN` is only for
`github-release`, which waits until the mirror has pushed the tag. Changes are never pushed
to GitHub directly; the mirror would overwrite them.

## Release checklist

- Changes go to `develop` first and reach `master` through a merge request; the tag is set
  on `master`.
- `CHANGELOG.md`: `## [X.Y.Z] - <date>` — the tag jobs fail without it, and
  `github-release` takes the notes from exactly that heading.
- The entry names the contained versions under `### Contents`, read from the image right
  before tagging:
  `docker run --rm --entrypoint sh epicsoft/smarthost:latest -c 'cat /etc/alpine-release; postconf mail_version; apk list -I libssl3'`
- `README.md`: the `## Versions` section, and on a new minor or major version the `X.Y` in
  the example.
- Tag **without `v`**: `X.Y.Z`.

## Conventions

- `.editorconfig`: LF, UTF-8, 2-space indent, final newline, trailing whitespace trimmed,
  120 columns (180 for YAML, unlimited for Markdown); `.gitattributes` keeps LF in the
  repository.
- `apk --no-cache upgrade` comes before `apk add`: `apk add` never upgrades the packages of
  the base image, so their security fixes would only arrive with the next base image.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `ci:`, `chore:`).
