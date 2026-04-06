# ZaloClaw Infra 🚀

🇻🇳 Vietnamese version: [README.vn.md](README.vn.md)

Spin up a production-ready OpenClaw Docker environment in minutes, with smarter model routing and useful tooling preinstalled.

> [!IMPORTANT]
> ⚡ **Want the fastest Zalo setup flow?** Use the companion UI project here: **[zaloclaw-ui](https://github.com/zaloclaw/zaloclaw-ui)**.

![ZaloClaw benefits](image/README/Zclawbenefit.png)

## Why this repo exists 🎯

This repository simplifies OpenClaw installation and day-1 operations by focusing on three practical goals:

1. Set up OpenClaw in Docker with a repeatable script-based flow.
2. Use a LiteLLM router so requests can be routed to lower-cost models when appropriate, instead of always using expensive models.
3. Preinstall common runtime tools and dependencies in the gateway container, including Playwright and gog CLI.

## What you get ✨

- 🐳 Automated OpenClaw Docker setup and startup.
- 🧠 LiteLLM configuration generation from your environment keys.
- ⚙️ Seeded OpenClaw config for browser, gateway, models, plugins, agents, and skills.
- 🎭 Playwright Linux dependencies and Chromium installation.
- 🛠️ gog CLI installed in the running gateway container.

## Prerequisites 📦

- macOS or Linux shell
- Docker + Docker Compose
- One or more model provider keys in your environment (OpenAI, Google, Anthropic, or OpenRouter)

## Quick Start ⚡

### 1) Set up environment 🧩

Create your environment file:

```bash
cp .env.example .env
```

Then edit .env and set at least:

- OPENCLAW_CONFIG_DIR
- OPENCLAW_WORKSPACE_DIR
- LITELLM_MASTER_KEY
- One provider API key (for example OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY)

The setup script validates these values and exits early if they are missing.
Other values in .env.example (for example ports and image tags) can keep their defaults.

### 2) Run the setup script ▶️

```bash
chmod +x zaloclaw-docker-setup.sh
./zaloclaw-docker-setup.sh
```

This script orchestrates the full setup:

- Generates LiteLLM config based on available API keys.
- Seeds OpenClaw configuration with sensible defaults.
- Starts OpenClaw gateway through Docker Compose.
- Installs Playwright system dependencies.
- Installs Chromium for Playwright.
- Installs gog CLI in the gateway container.

## After setup ✅

You should have:

- 🐳 OpenClaw gateway running in Docker.
- 🧭 A working LiteLLM smart router profile for complexity-based model selection.
- 🎭 Playwright + Chromium ready for browser automation workflows.
- 🛠️ gog CLI ready inside the gateway container.

To inspect logs:

```bash
docker compose logs -f openclaw-gateway
```

## Notes 📝

- If you rerun the script, it will reuse existing config where possible.
- Keep your .env file private and never commit real API keys.

## Author 👤

- Name: Hưng Nguyễn
- Description: Đam mê AI, thích tự động hoá và đơn gian mọi thứ
