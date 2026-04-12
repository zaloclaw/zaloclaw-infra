#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="$ROOT_DIR/.env"

# Build a local image that extends the official OpenClaw image with
# Playwright/Chromium and gog preinstalled.
OPENCLAW_DEFAULT_BASE_IMAGE="ghcr.io/openclaw/openclaw:2026.3.31"
OPENCLAW_DOCKERFILE="$ROOT_DIR/Dockerfile.zaloclaw"
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

OPENCLAW_BASE_IMAGE="$(read_env_value "OPENCLAW_IMAGE")"
OPENCLAW_BASE_IMAGE="${OPENCLAW_BASE_IMAGE:-$OPENCLAW_DEFAULT_BASE_IMAGE}"
OPENCLAW_BASE_VERSION="${OPENCLAW_BASE_IMAGE##*:}"
OPENCLAW_IMAGE="openclaw:${OPENCLAW_BASE_VERSION}-zaloclaw"
OPENCLAW_BOOTSTRAP_IMAGE="$OPENCLAW_BASE_IMAGE"

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

if not isinstance(cfg, dict):
		cfg = {}

had_agents = "agents" in cfg

template_seed = copy.deepcopy(template)
remote = template_seed.get("browser", {}).get("profiles", {}).get("remote", {})
if isinstance(remote, dict) and remote.get("cdpUrl") == "__OPENCLAW_REMOTE_CDP_URL__":
		remote["cdpUrl"] = cdp_url

allowed = template_seed.get("gateway", {}).get("controlUi", {}).get("allowedOrigins", [])
if isinstance(allowed, list):
		for i, origin in enumerate(allowed):
				if isinstance(origin, str) and "__OPENCLAW_GATEWAY_PORT__" in origin:
						allowed[i] = origin.replace("__OPENCLAW_GATEWAY_PORT__", gw_port)

merged_paths = []

def merge_missing(dst, src, path=()):
		if not isinstance(dst, dict) or not isinstance(src, dict):
				return
		for key, value in src.items():
				next_path = path + (key,)
				if had_agents and next_path == ("agents", "defaults", "workspace"):
						continue
				if key not in dst:
						dst[key] = copy.deepcopy(value)
						merged_paths.append(next_path)
						continue
				if isinstance(dst.get(key), dict) and isinstance(value, dict):
						merge_missing(dst[key], value, next_path)

merge_missing(cfg, template_seed)
if merged_paths:
		seeded.extend(sorted({path[0] for path in merged_paths if len(path) > 0}))

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

if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) {
	cfg = {};
}

const hadAgents = Object.prototype.hasOwnProperty.call(cfg, "agents");

const clone = (v) => JSON.parse(JSON.stringify(v));
const templateSeed = clone(template);

const remote = templateSeed?.browser?.profiles?.remote;
if (remote?.cdpUrl === "__OPENCLAW_REMOTE_CDP_URL__") {
	remote.cdpUrl = cdpUrl;
}

const allowedOrigins = templateSeed?.gateway?.controlUi?.allowedOrigins;
if (Array.isArray(allowedOrigins)) {
	templateSeed.gateway.controlUi.allowedOrigins = allowedOrigins.map((origin) =>
		typeof origin === "string" && origin.includes("__OPENCLAW_GATEWAY_PORT__")
			? origin.replace(/__OPENCLAW_GATEWAY_PORT__/g, gwPort)
			: origin
	);
}

const mergedPaths = [];
const mergeMissing = (dst, src, path = []) => {
	if (!dst || typeof dst !== "object" || Array.isArray(dst)) return;
	if (!src || typeof src !== "object" || Array.isArray(src)) return;
	for (const [k, v] of Object.entries(src)) {
		const nextPath = [...path, k];
		if (hadAgents && nextPath.length === 3 && nextPath[0] === "agents" && nextPath[1] === "defaults" && nextPath[2] === "workspace") {
			continue;
		}
		if (!(k in dst)) {
			dst[k] = clone(v);
			mergedPaths.push(nextPath);
			continue;
		}
		if (dst[k] && typeof dst[k] === "object" && !Array.isArray(dst[k]) && v && typeof v === "object" && !Array.isArray(v)) {
			mergeMissing(dst[k], v, nextPath);
		}
	}
};

mergeMissing(cfg, templateSeed);
if (mergedPaths.length > 0) {
	seeded.push(...Array.from(new Set(mergedPaths.filter((p) => p.length > 0).map((p) => p[0]))).sort());
}

const updateLitellmApiKey = (modelsObj) => {
	const providers = modelsObj && typeof modelsObj === "object" ? modelsObj.providers : undefined;
	const litellm = providers && typeof providers === "object" ? providers.litellm : undefined;
	if (!litellm || typeof litellm !== "object") return false;
	if (!["__LITELLM_MASTER_KEY__", "__LITELLM_API_KEY__"].includes(litellm.apiKey)) return false;
	if (!litellmMasterKey) return false;
	litellm.apiKey = litellmMasterKey;
	return true;
};
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

echo "==> Building custom OpenClaw image: $OPENCLAW_IMAGE"
docker build \
	--build-arg "OPENCLAW_BASE_IMAGE=$OPENCLAW_BASE_IMAGE" \
	-t "$OPENCLAW_IMAGE" \
	-f "$OPENCLAW_DOCKERFILE" \
	"$ROOT_DIR"

OPENCLAW_IMAGE="$OPENCLAW_BOOTSTRAP_IMAGE" \
OPENCLAW_HOME_VOLUME="$OPENCLAW_HOME_VOLUME" \
OPENCLAW_CONFIG_DIR="$OPENCLAW_CONFIG_DIR" \
OPENCLAW_WORKSPACE_DIR="$OPENCLAW_WORKSPACE_DIR" \
OPENCLAW_GATEWAY_PORT="$OPENCLAW_GATEWAY_PORT" \
OPENCLAW_REMOTE_CDP_URL="$OPENCLAW_REMOTE_CDP_URL" \
./docker-setup.sh

compose_args=(-f "$ROOT_DIR/docker-compose.yml")
if [[ -f "$ROOT_DIR/docker-compose.extra.yml" ]]; then
	compose_args+=(-f "$ROOT_DIR/docker-compose.extra.yml")
fi

echo "==> Recreating gateway with custom OpenClaw image: $OPENCLAW_IMAGE"
OPENCLAW_IMAGE="$OPENCLAW_IMAGE" docker compose "${compose_args[@]}" up -d --force-recreate openclaw-gateway

echo "==> Checking Playwright version in gateway container"
docker compose exec -T --user node openclaw-gateway sh -lc 'node -e "console.log(require(\"playwright-core/package.json\").version)"'

echo "==> Chromium executable path"
docker compose exec -T --user node openclaw-gateway sh -lc 'PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright node -e "const p=require(\"playwright-core\"); console.log(p.chromium.executablePath());"'

echo "==> Checking gog CLI version"
docker compose exec -T --user node openclaw-gateway sh -lc 'gog --version'

echo "==> Done. Browser deps, Chromium, and gog CLI are preinstalled in the custom image."
echo "==> Chromium cache path: /home/node/.cache/ms-playwright (persisted by OPENCLAW_HOME_VOLUME=$OPENCLAW_HOME_VOLUME)."
echo "==> gog CLI path: /usr/local/bin/gog"
