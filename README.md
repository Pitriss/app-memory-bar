# App Memory Bar

Plasma 6 widget for monitoring per-application cgroup memory and maintaining safe per-app memory budgets through a persistent `systemd --user` backend.

## Plugin ID

`cz.pitriss.appmemorybar`

## Build

```bash
./scripts/build-plasmoid.sh
```

Local `.plasmoid` builds are kept in `.plasmoids/`. This directory is intended as local build/history storage and should be excluded through `.git/info/exclude`.

## Install

```bash
kpackagetool6 -t Plasma/Applet -i .plasmoids/app-memory-bar-0.10.3.plasmoid
```

## Release

Releases are driven by the root helper. The tag version must match `KPlugin.Version` in `metadata.json`.

```bash
./app-memory-release v0.10.3
```

The helper requires a clean Git working tree and an authenticated `gh` CLI. It builds and verifies the `.plasmoid`, stores it in `.plasmoids/`, creates/pushes the annotated tag, and publishes the `.plasmoid` as a GitHub Release asset.

Pushing the tag triggers the tag-only `.github/workflows/release-deb.yml` workflow. There are no branch-push Debian builds. CI installs the Debian build/QA tools on the disposable runner, builds `plasma-widget-app-memory-bar_<version>_all.deb`, verifies its metadata and installed Plasma paths, and runs Lintian against the generated `.changes` file. Lintian errors or warnings fail the release job, so the `.deb` is attached to the GitHub Release only after all checks pass.

`./scripts/build-deb.sh` remains available for debugging the packaging, but normal releases do not require Debian build tools or Lintian on the workstation. Temporary Debian build files stay under `.tmp/deb-build/`.

## Debian package migration

The Debian package installs the plasmoid under `/usr/share/plasma/plasmoids/` and the backend as a packaged `systemd --user` service. A packaged migration service runs as the desktop user before the backend. If an older per-user installation with the same plugin ID exists, it backs up:

- `~/.local/share/plasma/plasmoids/cz.pitriss.appmemorybar/`
- `~/.config/systemd/user/app-memory-bar.service`

under `~/.local/state/app-memory-bar/migration-backup/` (or the corresponding XDG locations), then enables the packaged backend. Widget configuration and `~/.config/app-memory-bar/` are preserved. The migration never scans or modifies other users' home directories from package maintainer scripts.

Status can be checked manually with:

```bash
app-memory-bar-migrate --status
```

A migration can also be rerun manually as the desktop user:

```bash
app-memory-bar-migrate --migrate
```

Do not run the migrator through `sudo`.

## Upgrade from the old plugin ID

The pre-public namespace was `cz.chytrex.bravememorybar`. Install the new package first, then run:

```bash
bash scripts/migrate-from-chytrex-id.sh
```

After a successful migration, the old package can be removed:

```bash
kpackagetool6 -t Plasma/Applet -r cz.chytrex.bravememorybar
```

The backend application configuration remains in `~/.config/app-memory-bar/` and is reused.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
