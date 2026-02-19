# MTProxy One-Command Installer (Docker + FakeTLS)

Production-ready installer for **official Telegram MTProxy Docker image**: `telegrammessenger/proxy`.

No `mtg`, no third-party proxy daemons, no ad/affiliate logic.

## 1. One-line install

```bash
curl -sSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
```

## 2. How to get SECRET

```bash
openssl rand -hex 16
```

This outputs exactly 32 hex symbols (required by installer).

## 3. How to register proxy in `@MTProxybot`

1. Open Telegram and start `@MTProxybot`.
2. Use your server public IP and selected port (default `8443`).
3. Provide your generated `SECRET` when requested.
4. Copy the resulting `TAG` from the bot.
5. Run installer and paste that `TAG`.

## 4. How to set promoted channel

1. Configure promoted channel via `@MTProxybot` for your registered proxy.
2. Reuse/update the `TAG` if bot gives a new one.
3. Re-run `install.sh` safely (idempotent) to apply updates.

## 5. How to get connection link

Installer prints a final link in this format:

```text
tg://proxy?server=IP&port=PORT&secret=EE_SECRET_HEXDOMAIN
```

Where:
- `EE_SECRET_HEXDOMAIN = ee + SECRET + hex(TLS_DOMAIN)`
- Default TLS domain: `cloudflare.com`

Installer auto-detects public IPv4 and auto-converts TLS domain to hex.

## 6. Security notes

- Use only your own trusted server.
- Keep SSH (`22`) restricted where possible.
- Use strong random `SECRET` values.
- Re-run installer after changing `TAG`, `SECRET`, port, or domain.
- Script has no telemetry, ads, or external affiliate links.

## Repository structure

```text
.
├── install.sh
├── uninstall.sh
├── status.sh
├── README.md
└── .gitignore
```

## Usage

### Install / reconfigure

```bash
sudo bash install.sh
```

### Status

```bash
bash status.sh
```

### Uninstall MTProxy container

```bash
sudo bash uninstall.sh
```

## Local repo setup commands

```bash
git init
git add .
git commit -m "mtproxy installer"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

## Non-interactive example

```bash
SECRET=... TAG=... CLIENT_PORT=8443 TLS_DOMAIN=cloudflare.com WORKERS=1 \
  curl -sSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
```
