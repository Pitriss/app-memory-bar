# App Memory Bar

Plasma 6 widget for monitoring per-application cgroup memory and maintaining safe per-app memory budgets through a persistent `systemd --user` backend.

## Plugin ID

`cz.pitriss.appmemorybar`

## Build

```bash
./scripts/build-plasmoid.sh
```

The package is created in `dist/`.

## Install

```bash
kpackagetool6 -t Plasma/Applet -i dist/app-memory-bar-0.10.0.plasmoid
```

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
