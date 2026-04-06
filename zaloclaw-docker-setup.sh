#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="$ROOT_DIR/.env"

# Use the official prebuilt image and persist /home/node so Playwright browser
# downloads survive one-off `docker compose run` containers.
OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:2026.3.31"
OPENCLAW_HOME_VOLUME="openclaw_home"

LITELLM_SETUP_SCRIPT="$ROOT_DIR/litellm/llm-setup.sh"
LITELLM_CONFIG_FILE="$ROOT_DIR/litellm/litellm-config.yaml"

read_env_value() {
	local key="$1"
	local env_path="$ENV_PATH"
	local value="${!key:-}"

	if [[ -n "$value" ]]; then
		echo "$value"
		return 0
	fi

	if [[ ! -f "$env_path" ]]; then
		return 0
	fi

	value="$(grep -E "^${key}=" "$env_path" | tail -n 1 | cut -d '=' -f2- || true)"
	value="${value%\"}"
	value="${value#\"}"
	value="${value%\'}"
	value="${value#\'}"
	echo "$value"
}

validate_required_env() {
	local required_vars=(
		"OPENCLAW_CONFIG_DIR"
		"OPENCLAW_WORKSPACE_DIR"
		"LITELLM_MASTER_KEY"
	)
	local provider_vars=(
		"OPENAI_API_KEY"
		"GOOGLE_API_KEY"
		"ANTHROPIC_API_KEY"
		"OPENROUTER_API_KEY"
	)
	local missing_vars=()
	local key=""
	local provider_present=0

	for key in "${required_vars[@]}"; do
		if [[ -z "$(read_env_value "$key")" ]]; then
			missing_vars+=("$key")
		fi
	done

	for key in "${provider_vars[@]}"; do
		if [[ -n "$(read_env_value "$key")" ]]; then
			provider_present=1
			break
		fi
	done

	if (( ${#missing_vars[@]} > 0 )) || (( provider_present == 0 )); then
		echo "ERROR: Missing required configuration in $ENV_PATH (or exported env vars)." >&2
		if (( ${#missing_vars[@]} > 0 )); then
			echo "  Required variables not set: ${missing_vars[*]}" >&2
		fi
		if (( provider_present == 0 )); then
			echo "  Set at least one provider key: OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY" >&2
		fi
		exit 1
	fi
}

validate_required_env

OPENCLAW_CONFIG_DIR="$(read_env_value "OPENCLAW_CONFIG_DIR")"

OPENCLAW_WORKSPACE_DIR="$(read_env_value "OPENCLAW_WORKSPACE_DIR")"

OPENCLAW_GATEWAY_PORT="$(read_env_value "OPENCLAW_GATEWAY_PORT")"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

OPENCLAW_REMOTE_CDP_URL="$(read_env_value "OPENCLAW_REMOTE_CDP_URL")"
OPENCLAW_REMOTE_CDP_URL="${OPENCLAW_REMOTE_CDP_URL:-http://192.168.65.254:9222}"

ensure_litellm_config() {
	if [[ ! -x "$LITELLM_SETUP_SCRIPT" ]]; then
		echo "==> Making llm-setup.sh executable"
		chmod +x "$LITELLM_SETUP_SCRIPT"
	fi

	echo "==> Generating LiteLLM configuration via llm-setup.sh"
	if ! "$LITELLM_SETUP_SCRIPT"; then
		echo "ERROR: Failed to generate LiteLLM config. Configure API keys in .env and rerun." >&2
		exit 1
	fi

	if [[ ! -s "$LITELLM_CONFIG_FILE" ]]; then
		echo "ERROR: Missing or empty $LITELLM_CONFIG_FILE after llm-setup.sh." >&2
		exit 1
	fi
}

seed_openclaw_config() {
	local template_path="$ROOT_DIR/seed_openclaw.json"
	local config_path="$OPENCLAW_CONFIG_DIR/openclaw.json"
	local litellm_master_key=""

	litellm_master_key="$(read_env_value "LITELLM_MASTER_KEY")"

	if [[ ! -f "$template_path" ]]; then
		echo "WARNING: Missing template $template_path, skipping predefined config seeding." >&2
		return 0
	fi

	mkdir -p "$OPENCLAW_CONFIG_DIR"
	mkdir -p "$OPENCLAW_WORKSPACE_DIR"

	local skills_src="$ROOT_DIR/skills"
	if [[ -d "$skills_src" ]]; then
		echo "==> Copying skills to $OPENCLAW_WORKSPACE_DIR/skills"
		mkdir -p "$OPENCLAW_WORKSPACE_DIR/skills"
		cp -r "$skills_src/." "$OPENCLAW_WORKSPACE_DIR/skills/"
	fi

	if command -v python3 >/dev/null 2>&1; then
		python3 - "$template_path" "$config_path" "$OPENCLAW_REMOTE_CDP_URL" "$OPENCLAW_GATEWAY_PORT" "$OPENCLAW_WORKSPACE_DIR" "$litellm_master_key" <<'PY'
import copy
import json
import sys

template_path, config_path, cdp_url, gw_port, workspace_dir, litellm_master_key = sys.argv[1:7]

with open(template_path, "r", encoding="utf-8") as f:
		template = json.load(f)

cfg = {}
try:
		with open(config_path, "r", encoding="utf-8") as f:
				cfg = json.load(f)
except Exception:
		pass

seeded = []

def update_litellm_api_key(models_obj):
		providers = models_obj.get("providers", {}) if isinstance(models_obj, dict) else {}
		litellm = providers.get("litellm") if isinstance(providers, dict) else None
		if not isinstance(litellm, dict):
				return False
		if litellm.get("apiKey") not in ("__LITELLM_MASTER_KEY__", "__LITELLM_API_KEY__"):
				return False
		if not litellm_master_key:
				return False
		litellm["apiKey"] = litellm_master_key
		return True

if "browser" not in cfg:
		browser = copy.deepcopy(template.get("browser", {}))
		remote = browser.get("profiles", {}).get("remote", {})
		if remote.get("cdpUrl") == "__OPENCLAW_REMOTE_CDP_URL__":
				remote["cdpUrl"] = cdp_url
		cfg["browser"] = browser
		seeded.append("browser")

if "gateway" not in cfg:
		gateway = copy.deepcopy(template.get("gateway", {}))
		allowed = gateway.get("controlUi", {}).get("allowedOrigins", [])
		for i, origin in enumerate(allowed):
				if "__OPENCLAW_GATEWAY_PORT__" in origin:
						allowed[i] = origin.replace("__OPENCLAW_GATEWAY_PORT__", gw_port)
		cfg["gateway"] = gateway
		seeded.append("gateway")

if "skills" not in cfg:
		skills = copy.deepcopy(template.get("skills", {}))
		cfg["skills"] = skills
		seeded.append("skills")

if "plugins" not in cfg:
		cfg["plugins"] = copy.deepcopy(template.get("plugins", {}))
		seeded.append("plugins")

if "models" not in cfg:
		cfg["models"] = copy.deepcopy(template.get("models", {}))
		seeded.append("models")

if "agents" not in cfg:
		cfg["agents"] = copy.deepcopy(template.get("agents", {}))
		seeded.append("agents")
else:
		tpl_agents = template.get("agents", {})
		cfg_agents = cfg["agents"]
		tpl_defaults = tpl_agents.get("defaults", {})
		cfg_defaults = cfg_agents.setdefault("defaults", {})
		added = [k for k in tpl_defaults if k not in cfg_defaults and k != "workspace"]
		for k in added:
				cfg_defaults[k] = copy.deepcopy(tpl_defaults[k])
		if added:
				seeded.append("agents.defaults.merge")
		if "list" not in cfg_agents and "list" in tpl_agents:
				cfg_agents["list"] = copy.deepcopy(tpl_agents["list"])
				seeded.append("agents.list")

if update_litellm_api_key(cfg.get("models", {})):
		seeded.append("models.litellm.apiKey")

if seeded:
		with open(config_path, "w", encoding="utf-8") as f:
				json.dump(cfg, f, indent=2)
				f.write("\n")
		print("==> Seeded OpenClaw config sections:", ", ".join(seeded))
else:
		print("==> OpenClaw config already has predefined sections; nothing to seed.")
PY
		return 0
	fi

	if command -v node >/dev/null 2>&1; then
		node - "$template_path" "$config_path" "$OPENCLAW_REMOTE_CDP_URL" "$OPENCLAW_GATEWAY_PORT" "$OPENCLAW_WORKSPACE_DIR" "$litellm_master_key" <<'NODE'
const fs = require("node:fs");
const [templatePath, configPath, cdpUrl, gwPort, workspaceDir, litellmMasterKey] = process.argv.slice(2);

const template = JSON.parse(fs.readFileSync(templatePath, "utf8"));
let cfg = {};
try {
	cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
} catch {}

const seeded = [];

const updateLitellmApiKey = (modelsObj) => {
	const providers = modelsObj && typeof modelsObj === "object" ? modelsObj.providers : undefined;
	const litellm = providers && typeof providers === "object" ? providers.litellm : undefined;
	if (!litellm || typeof litellm !== "object") return false;
	if (!["__LITELLM_MASTER_KEY__", "__LITELLM_API_KEY__"].includes(litellm.apiKey)) return false;
	if (!litellmMasterKey) return false;
	litellm.apiKey = litellmMasterKey;
	return true;
};

if (!("browser" in cfg)) {
	const browser = JSON.parse(JSON.stringify(template.browser ?? {}));
	const remote = browser?.profiles?.remote;
	if (remote?.cdpUrl === "__OPENCLAW_REMOTE_CDP_URL__") {
		remote.cdpUrl = cdpUrl;
	}
	cfg.browser = browser;
	seeded.push("browser");
}

if (!("gateway" in cfg)) {
	const gateway = JSON.parse(JSON.stringify(template.gateway ?? {}));
	const allowed = gateway?.controlUi?.allowedOrigins;
	if (Array.isArray(allowed)) {
		gateway.controlUi.allowedOrigins = allowed.map((origin) =>
			origin.includes("__OPENCLAW_GATEWAY_PORT__")
				? origin.replace(/__OPENCLAW_GATEWAY_PORT__/g, gwPort)
				: origin
		);
	}
	cfg.gateway = gateway;
	seeded.push("gateway");
}

if (!("skills" in cfg)) {
	const skills = JSON.parse(JSON.stringify(template.skills ?? {}));
	cfg.skills = skills;
	seeded.push("skills");
}

if (!("plugins" in cfg)) {
	cfg.plugins = JSON.parse(JSON.stringify(template.plugins ?? {}));
	seeded.push("plugins");
}

if (!("models" in cfg)) {
	cfg.models = JSON.parse(JSON.stringify(template.models ?? {}));
	seeded.push("models");
}

if (!("agents" in cfg)) {
	cfg.agents = JSON.parse(JSON.stringify(template.agents ?? {}));
	seeded.push("agents");
} else {
	const tplAgents = template.agents ?? {};
	const cfgAgents = cfg.agents;
	const tplDefaults = tplAgents.defaults ?? {};
	cfgAgents.defaults ??= {};
	const added = Object.keys(tplDefaults).filter((k) => k !== "workspace" && !(k in cfgAgents.defaults));
	for (const k of added) {
		cfgAgents.defaults[k] = JSON.parse(JSON.stringify(tplDefaults[k]));
	}
	if (added.length > 0) seeded.push("agents.defaults.merge");
	if (!("list" in cfgAgents) && "list" in tplAgents) {
		cfgAgents.list = JSON.parse(JSON.stringify(tplAgents.list));
		seeded.push("agents.list");
	}
}

if (updateLitellmApiKey(cfg.models)) {
	seeded.push("models.litellm.apiKey");
}

if (seeded.length > 0) {
	fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + "\n");
	console.log("==> Seeded OpenClaw config sections:", seeded.join(", "));
} else {
	console.log("==> OpenClaw config already has predefined sections; nothing to seed.");
}
NODE
		return 0
	fi

	echo "WARNING: python3/node unavailable, cannot seed predefined OpenClaw config." >&2
	return 0
}

seed_openclaw_config
ensure_litellm_config

OPENCLAW_IMAGE="$OPENCLAW_IMAGE" \
OPENCLAW_HOME_VOLUME="$OPENCLAW_HOME_VOLUME" \
OPENCLAW_CONFIG_DIR="$OPENCLAW_CONFIG_DIR" \
OPENCLAW_WORKSPACE_DIR="$OPENCLAW_WORKSPACE_DIR" \
OPENCLAW_GATEWAY_PORT="$OPENCLAW_GATEWAY_PORT" \
OPENCLAW_REMOTE_CDP_URL="$OPENCLAW_REMOTE_CDP_URL" \
./docker-setup.sh

echo "==> Installing Playwright Linux runtime dependencies in gateway container"
docker compose exec -T --user root openclaw-gateway sh -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libdbus-1-3 libcups2 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2'

echo "==> Checking Playwright version in gateway container"
docker compose exec -T --user node openclaw-gateway sh -lc 'node -e "console.log(require(\"playwright-core/package.json\").version)"'

echo "==> Installing Chromium via Playwright"
docker compose exec -T --user node openclaw-gateway sh -lc 'PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright node /app/node_modules/playwright-core/cli.js install chromium'

echo "==> Chromium executable path"
docker compose exec -T --user node openclaw-gateway sh -lc 'PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright node -e "const p=require(\"playwright-core\"); console.log(p.chromium.executablePath());"'

echo "==> Installing gog CLI dependencies in gateway container"
docker compose exec -T --user root openclaw-gateway sh -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl tar'

echo "==> Installing gog CLI (official prebuilt release)"
docker compose exec -T --user root openclaw-gateway sh -lc '
set -e
version="0.12.0"
case "$(uname -m)" in
	x86_64|amd64) arch="amd64" ;;
	aarch64|arm64) arch="arm64" ;;
	*)
		echo "ERROR: Unsupported architecture for gog prebuilt install: $(uname -m)" >&2
		exit 1
		;;
esac

url="https://github.com/steipete/gogcli/releases/download/v${version}/gogcli_${version}_linux_${arch}.tar.gz"
tmpdir="$(mktemp -d)"
trap "rm -rf \"$tmpdir\"" EXIT

curl -fsSL "$url" -o "$tmpdir/gogcli.tar.gz"
tar -xzf "$tmpdir/gogcli.tar.gz" -C "$tmpdir"
install -m 0755 "$tmpdir/gog" /usr/local/bin/gog
'

echo "==> Checking gog CLI version"
docker compose exec -T --user node openclaw-gateway sh -lc 'gog --version'

echo "==> Done. Browser deps, Chromium, and gog CLI installed in running gateway container."
echo "==> Chromium cache path: /home/node/.cache/ms-playwright (persisted by OPENCLAW_HOME_VOLUME=$OPENCLAW_HOME_VOLUME)."
echo "==> gog CLI path: /usr/local/bin/gog"
