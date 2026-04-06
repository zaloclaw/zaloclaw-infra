# Release Notes

## v1.0.0 - First Release (2026-04-06)

### Highlights

- Initial release of ZaloClaw Infra.
- Provides a streamlined way to install and run OpenClaw with Docker.
- Includes LiteLLM smart routing to avoid always using high-cost models.
- Preinstalls key runtime dependencies and tools, including Playwright and gog CLI.

### What is included

- One-command orchestration via `zaloclaw-docker-setup.sh`.
- Environment-based setup using `.env` and `.env.example`.
- Automatic LiteLLM configuration generation from available provider keys.
- OpenClaw configuration seeding (gateway, browser, models, agents, plugins, skills).
- Gateway startup and post-setup runtime provisioning in Docker containers.

### Quick start

1. Set up environment:

```bash
cp .env.example .env
# then update API keys and LITELLM_MASTER_KEY
```

2. Run setup:

```bash
chmod +x zaloclaw-docker-setup.sh
./zaloclaw-docker-setup.sh
```

### Notes

- Keep `.env` private and do not commit real secrets.
- This release focuses on fast local bootstrap and practical default automation.
