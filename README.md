# uptime-go

`uptime-go` is a lightweight uptime monitor written in Go for low-resource environments (small VPS, homelab nodes, and minimal servers).

It is inspired by Uptime Kuma, but designed for users who want a simple native binary instead of running a full containerized monitoring stack.

---

## Why this project exists

I wanted monitoring for my homelab without the overhead of a larger service.  
This project focuses on:

- low memory/CPU usage
- simple setup
- easy self-hosting
- practical notifications for downtime

---

## Current functionality

At its core, `uptime-go` provides a minimal uptime-checking workflow for self-hosted systems.

### What it does

- Runs as a small Go application
- Performs uptime checks for configured services/hosts
- Reports service status (up/down) in a lightweight way
- Targets resource-constrained deployments (e.g., tiny VPS)

> If you are running this project today, think of it as a minimal monitoring core that can be expanded with notifications and scheduling.

---

## Installation

1. Download a release archive:

Linux amd64:

```bash
curl -fL -o uptime-go_linux_amd64.tar.gz https://github.com/Tacoden/uptime-go/releases/latest/download/uptime-go_linux_amd64.tar.gz
```

2. Create a folder and extract the archive into it.

For amd64:

```bash
mkdir -p uptime-go
tar -xzf uptime-go_linux_amd64.tar.gz -C uptime-go
```

3. Change into the extracted folder:

```bash
cd uptime-go-release
```

4. Run the installer:

```bash
chmod +x install.sh
./install.sh
```

What the installer does:

- Uses the local release files you extracted
- Installs files into `/opt/uptime-go`
- Tries to enable ping socket capability via `setcap`
- Falls back to root mode if capability setup is not available
- Optionally configures a `systemd` service for 24/7 auto-start

At the end, it prints the config path:

```bash
/opt/uptime-go/config.json
```

Edit that file and add your settings before running in production.

then enter sudo systemctl restart uptime-go


