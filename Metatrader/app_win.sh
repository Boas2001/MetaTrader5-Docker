#!/bin/bash
set -euo pipefail

echo "[APP-WIN] Initializing Windows/Wine application..."

# --- expects Wine Python already installed by start.sh ---
# Prefer explicit WINE_EXE; otherwise autodetect Kron4ek Wine
if [ -n "${WINE_EXE:-}" ]; then
  wine_executable="$WINE_EXE"
else
  KRON_WINE_DIR="${KRON_WINE_DIR:-/opt/wine-kron4ek}"
  kron_wine="$(ls -d ${KRON_WINE_DIR}/wine-* 2>/dev/null | head -n1)/bin/wine"
  if [ -x "$kron_wine" ]; then
    wine_executable="$kron_wine"
  else
    wine_executable="wine"
  fi
fi

echo "[APP-WIN] Using wine: $wine_executable"

# Use winepath from the same Wine distribution (Kron4ek)
winepath_executable="$(dirname "$wine_executable")/winepath"
if [ ! -x "$winepath_executable" ]; then
  echo "[APP-WIN] winepath not found at: $winepath_executable"
  echo "[APP-WIN] Hint: set WINE_EXE to Kron4ek wine, e.g. /opt/wine-kron4ek/.../bin/wine"
  exit 1
fi

# This must match what you set in start.sh
wine_python_dir="${WINE_PY_DIR:-C:\\Python313}"
wine_python_exe="${WINE_PY_EXE:-${wine_python_dir}\\python.exe}"

# Repo + app config (override via compose .env)
APP_DIR="${APP_DIR:-/config/app}"
APP_ENTRY="${APP_ENTRY:-main.py}"         # relative to repo root
APP_ENV_FILE="${APP_ENV_FILE:-${APP_DIR}/.env}"
APP_ENV_TEMPLATE="${APP_ENV_TEMPLATE:-${APP_DIR}/.env.example}"

PRIVATE_GIT_REPO="${PRIVATE_GIT_REPO:-}"  # e.g. github.com/ORG/REPO.git
PRIVATE_GIT_REF="${PRIVATE_GIT_REF:-main}"

# Windows venv location (stored in /config so it persists)
APP_VENV_DIR="${APP_VENV_DIR:-/config/app-venv-win}"

# --- Checks ---
if ! command -v git >/dev/null 2>&1; then
  echo "[APP-WIN] git not found – installing..."
  apt-get update
  apt-get install -y --no-install-recommends git
  rm -rf /var/lib/apt/lists/*
fi

if [ -z "$PRIVATE_GIT_REPO" ]; then
  echo "[APP-WIN] PRIVATE_GIT_REPO not set"
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[APP-WIN] GITHUB_TOKEN not set"
  exit 1
fi

# --- Clone / update repo (Linux side; just files) ---
if [ ! -d "${APP_DIR}/.git" ]; then
  echo "[APP-WIN] Cloning repo into ${APP_DIR}"
  rm -rf "$APP_DIR"
  git clone "https://oauth2:${GITHUB_TOKEN}@${PRIVATE_GIT_REPO}" "$APP_DIR"
  git -C "$APP_DIR" checkout "$PRIVATE_GIT_REF" >/dev/null 2>&1 || true
else
  echo "[APP-WIN] Updating repo in ${APP_DIR}"
  git -C "$APP_DIR" fetch --all --prune
  git -C "$APP_DIR" checkout "$PRIVATE_GIT_REF" >/dev/null 2>&1 || true
  git -C "$APP_DIR" pull --ff-only || true
fi

# --- Prepare Windows paths ---
APP_DIR_WIN="$("$winepath_executable" -w "$APP_DIR")"
APP_VENV_DIR_WIN="$("$winepath_executable" -w "$APP_VENV_DIR")"

REQ_TXT_LINUX="${APP_DIR}/requirements.txt"
REQ_TXT_WIN="$("$winepath_executable" -w "$REQ_TXT_LINUX")"

ENTRY_LINUX="${APP_DIR}/${APP_ENTRY}"
ENTRY_WIN="$("$winepath_executable" -w "$ENTRY_LINUX")"

# venv python.exe path in Windows
VENV_PY_WIN="${APP_VENV_DIR_WIN}\\Scripts\\python.exe"

# --- Ensure requirements.txt exists ---
if [ ! -f "$REQ_TXT_LINUX" ]; then
  echo "[APP-WIN] requirements.txt not found at: $REQ_TXT_LINUX"
  exit 1
fi

# --- Ensure Wine Python exists ---
if ! "$wine_executable" "$wine_python_exe" -c "import sys; print(sys.version)" >/dev/null 2>&1; then
  echo "[APP-WIN] Wine Python not working at: $wine_python_exe"
  echo "[APP-WIN] Make sure start.sh installed Python 3.13.8 into C:\\Python313"
  exit 1
fi

# --- Create Windows venv if missing ---
if [ ! -d "$APP_VENV_DIR" ]; then
  echo "[APP-WIN] Creating Windows venv at ${APP_VENV_DIR} (Wine path: ${APP_VENV_DIR_WIN})"
  mkdir -p "$APP_VENV_DIR"
  "$wine_executable" "$wine_python_exe" -m venv "$APP_VENV_DIR_WIN"
fi

# --- Install requirements into the Windows venv ---
echo "[APP-WIN] Installing requirements into Windows venv..."
"$wine_executable" "$VENV_PY_WIN" -m pip install --upgrade --no-cache-dir pip
"$wine_executable" "$VENV_PY_WIN" -m pip install --no-cache-dir -r "$REQ_TXT_WIN"

# --- First-run .env handling (Linux file, used by your app code) ---
# --- First-run .env handling + "configured" guard ---
ENV_READY_KEY="${ENV_READY_KEY:-APP_ENV_CONFIGURED}"
ENV_READY_VALUE="${ENV_READY_VALUE:-true}"

if [ ! -f "$APP_ENV_FILE" ]; then
  echo "[APP-WIN] App .env not found: $APP_ENV_FILE"
  if [ -f "$APP_ENV_TEMPLATE" ]; then
    echo "[APP-WIN] Copying template -> .env (first run)"
    cp "$APP_ENV_TEMPLATE" "$APP_ENV_FILE"
  else
    echo "[APP-WIN] No template found. Creating empty .env."
    touch "$APP_ENV_FILE"
  fi

  echo ""
  echo "================================================="
  echo "ACTION REQUIRED:"
  echo "1) Edit ./config/app/.env"
  echo "2) Set ${ENV_READY_KEY}=${ENV_READY_VALUE}"
  echo "3) Restart: docker compose restart"
  echo "================================================="
  echo ""
  exit 1
fi

# If .env exists, require explicit confirmation flag
if ! grep -Eq "^[[:space:]]*${ENV_READY_KEY}[[:space:]]*=[[:space:]]*${ENV_READY_VALUE}[[:space:]]*$" "$APP_ENV_FILE"; then
  echo ""
  echo "================================================="
  echo "CONFIG NOT CONFIRMED:"
  echo "Your app .env exists, but is not marked as configured."
  echo ""
  echo "Please edit:"
  echo "  ./config/app/.env"
  echo ""
  echo "and add/set:"
  echo "  ${ENV_READY_KEY}=${ENV_READY_VALUE}"
  echo ""
  echo "Then restart: docker compose restart"
  echo "================================================="
  echo ""
  exit 1
fi

# --- Start app using Windows venv python ---
if [ ! -f "$ENTRY_LINUX" ]; then
  echo "[APP-WIN] Entry not found: $ENTRY_LINUX"
  exit 1
fi

echo "[APP-WIN] Starting app with Wine venv Python via cmd.exe..."

CMD_EXE="C:\\Windows\\System32\\cmd.exe"
APP_DIR_WIN="$("$winepath_executable" -w "$APP_DIR")"

"$wine_executable" "$CMD_EXE" /c "cd /d \"$APP_DIR_WIN\" && \"$VENV_PY_WIN\" \"$ENTRY_WIN\"" &

echo "[APP-WIN] App started."

