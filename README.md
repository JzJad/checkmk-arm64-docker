# checkmk-arm64-docker

[![Docker](https://github.com/JzJad/checkmk-arm64-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/JzJad/checkmk-arm64-docker/actions/workflows/docker-publish.yml)

Checkmk as a Docker container for arm64 devices such as the Raspberry Pi 4/5 and Oracle Ampere A1.

Checkmk does not publish ARM packages. This image installs the packages built from the official Checkmk
sources by [sergiodadi/check-mk-raspberry](https://github.com/sergiodadi/check-mk-raspberry), and otherwise follows
the [official Checkmk image](https://github.com/Checkmk/checkmk/tree/master/docker_image) (same entrypoint,
environment variables and hooks). Two variants of the Community edition are published:

| Variant | Base image |
|---|---|
| `debian` (default) | Debian 13 trixie |
| `ubuntu` | Ubuntu 24.04 noble, like the official Checkmk image |

The packages are pinned with their SHA-256 in [versions.json](versions.json). A weekly job opens a PR when upstream
publishes a new version (or re-uploads a package); merging it publishes new images.

## Quick start

```
docker run -d --name checkmk --restart unless-stopped \
    -p 5000:5000 -p 8000:8000 \
    -v checkmk-sites:/omd/sites \
    --tmpfs /opt/omd/sites/cmk/tmp:uid=1000,gid=1000 \
    ghcr.io/jzjad/checkmk-arm64-docker:latest
```

Or with [compose.yaml](compose.yaml): `docker compose up -d`.

Open `http://<host>:5000/cmk/` and log in as `cmkadmin`. Unless you set `CMK_PASSWORD`, the generated password is
printed in the container log on first start: `docker logs checkmk`.

## Tags

| Debian | Ubuntu | Meaning |
|---|---|---|
| `latest`, `debian` | `ubuntu` | Newest published version |
| `2.5`, `2.5-debian` | `2.5-ubuntu` | Newest patch release of 2.5 |
| `2.5.0p15`, `2.5.0p15-debian` | `2.5.0p15-ubuntu` | Exact version |

The untagged-variant tags (`latest`, `2.5`, `2.5.0p15`) belong to the entry with `"latest": true` in
[versions.json](versions.json); the build fails unless exactly one entry has it.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `CMK_SITE_ID` | `cmk` | Name of the site (and of the URL path) |
| `CMK_PASSWORD` | random | Password of `cmkadmin`, only used when the site is created |
| `TZ` | | Timezone of the site, e.g. `Europe/Berlin` |
| `MAIL_RELAY_HOST` | | Smart host for outgoing notification mails |
| `CMK_LIVESTATUS_TCP` | | `on` enables Livestatus on port 6557 (set at site creation) |
| `CMK_BACKUP_ON_UPDATE` | | `on` writes a tarball of the site to `/backups` before each update |

## Ports and volumes

| | |
|---|---|
| `5000` | Web interface |
| `8000` | Agent receiver (needed to register agents) |
| `6557` | Livestatus, if enabled |
| `/omd/sites` | Site data — keep this on a volume |
| `/backups` | Pre-update backups, if `CMK_BACKUP_ON_UPDATE=on` |

## Updating

Pull the new image and recreate the container with the same volume:

```
docker compose pull && docker compose up -d
```

On start the entrypoint sees that the site belongs to an older version and runs `omd update` automatically.
Checkmk only supports updating one major version at a time (e.g. 2.5 → 2.6, not 2.5 → 2.7), so when a new major
version comes out, update to it before the next one.

## Hooks

As in the official image, executable files in `/docker-entrypoint.d/<hook>/` are run at `pre-entrypoint`,
`pre-create`, `post-create`, `pre-update`, `post-update`, `pre-start` and `post-start`. The image ships
`pre-update/00-backup`; mounting your own directory over `/docker-entrypoint.d` replaces it.

## Building

The build needs an arm64 machine (or QEMU emulation):

```
scripts/build.sh debian            # builds checkmk-arm64:debian from versions.json
scripts/smoke-test.sh checkmk-arm64:debian
```

`scripts/check-upstream.sh` updates [versions.json](versions.json) to the newest upstream packages (needs `gh` and
`jq`). To add a variant, add an entry there; the workflow builds one image per entry.

## Credits

- [Checkmk](https://checkmk.com), licensed under the GNU GPL v2. `docker-entrypoint.sh` is taken unchanged from the
  official image.
- [sergiodadi](https://github.com/sergiodadi/check-mk-raspberry) for building and publishing the arm64 packages.
- [chrisss404](https://github.com/chrisss404/check-mk-arm), whose packages were the base of the previous version of
  this project ([JzJad/rpi-checkmk](https://github.com/JzJad/rpi-checkmk)).
