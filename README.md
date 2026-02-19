# MTProxy Installer (Official Telegram Source Build)

This repository installs MTProxy the same way as the official `TelegramMessenger/MTProxy` guide: build from source and run `mtproto-proxy` with systemd.

## One-line install

```bash
curl -sSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
```

## What this installer does

1. Detects Ubuntu/Debian.
2. Installs official build dependencies from Telegram guide.
3. Clones/updates `https://github.com/TelegramMessenger/MTProxy` into `/opt/MTProxy`.
4. Builds with `make`.
5. Downloads:
   - `https://core.telegram.org/getProxySecret` -> `proxy-secret`
   - `https://core.telegram.org/getProxyConfig` -> `proxy-multi.conf`
6. Installs daily auto-refresh for `proxy-multi.conf` via `systemd timer` (`MTProxyConfigUpdate.timer`).
7. Asks interactively for:
   - user `SECRET` (32 hex, or auto-generate)
   - `TAG` from `@MTProxybot` (optional)
   - client port (`-H`, default `443`)
   - local stats port (`-p`, default `8888`)
   - worker count (`-M`, default `1`)
8. Creates and enables `/etc/systemd/system/MTProxy.service`.

## Generate SECRET manually

```bash
openssl rand -hex 16
```

## Register in @MTProxybot

1. Open `@MTProxybot` in Telegram.
2. Register your server and port.
3. Add promoted channel if needed.
4. Copy tag and re-run installer to set `-P <tag>`.

## Connection links

Installer prints:

```text
tg://proxy?server=IP&port=PORT&secret=SECRET
tg://proxy?server=IP&port=PORT&secret=ddSECRET
```

`dd` variant enables random padding on client side.

## Status / Uninstall

```bash
bash status.sh
sudo bash uninstall.sh
```

## Daily config refresh

`install.sh` also creates:

- `/usr/local/bin/mtproxy-refresh-config.sh`
- `/etc/systemd/system/MTProxyConfigUpdate.service`
- `/etc/systemd/system/MTProxyConfigUpdate.timer`

The timer runs daily (`OnCalendar=daily`) and refreshes `proxy-multi.conf` as recommended in the official MTProxy README.

## Push to GitHub

```bash
git init
git add .
git commit -m "mtproxy installer"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

## Notes

- This setup intentionally follows official source-based MTProxy flow.
- Re-run `install.sh` anytime to rotate secret/tag/ports.
