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
