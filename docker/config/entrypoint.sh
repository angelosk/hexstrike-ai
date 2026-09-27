#!/usr/bin/env bash
# HexStrike MCP minimal entrypoint
# - Start server immediately
# - Background update of security databases (best-effort)

set -euo pipefail

log()       { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
log_error() { printf '[%s] ERROR: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }

# --- Metasploit DB bootstrap (one-time, idempotent) ---
# Behavior:
# - If MSF_DB_URL is empty or unset, skip DB bootstrap (not an error).
# - If an active DB connection is already configured (db_status), skip bootstrap.
# - Otherwise, connect once and persist settings via db_save (stored under /root/.msf4).
if [ -z "${MSF_DB_URL:-}" ]; then
  log "[msf] MSF_DB_URL is not set; skipping Metasploit DB bootstrap."
else
  if ! command -v msfconsole >/dev/null 2>&1; then
    log_error "[msf] msfconsole not found in PATH; cannot bootstrap DB."
  else
    log "[msf] Checking current Metasploit DB status…"
    if msfconsole -qx 'db_status; exit -y' | grep -q 'Connected to'; then
      log "[msf] A data service is already configured; skipping bootstrap."
    else
      log "[msf] Initializing Metasploit DB config via db_connect…"
      mkdir -p /root/.msf4
      if msfconsole -qx "db_connect ${MSF_DB_URL}; db_save; db_status; exit -y"; then
        log "[msf] Metasploit DB configured and persisted."
      else
        log_error "[msf] db_connect failed; leaving Metasploit unconfigured."
      fi
    fi
  fi
fi

# --- Background updater (logs go to container stdout/stderr) ---
if command -v /usr/local/bin/update-tools-databases.sh >/dev/null 2>&1; then
  { /usr/local/bin/update-tools-databases.sh; } &
else
  log_error "[updater] /usr/local/bin/update-tools-databases.sh not found or not executable."
fi

# --- Authentication token (container must boot after the security hardening) ---
# The server fails closed at import if HEXSTRIKE_API_TOKEN is unset (it refuses
# to run unauthenticated). gunicorn imports hexstrike_server:app below, so the
# token must be present now. Use the operator-supplied value when given; else
# mint an ephemeral one and log it so it can be set as X-HexStrike-Token in the
# MCP client. Pin your own in docker/.env to keep it stable across restarts.
if [ -z "${HEXSTRIKE_API_TOKEN:-}" ]; then
  if command -v openssl >/dev/null 2>&1; then
    HEXSTRIKE_API_TOKEN="$(openssl rand -hex 32)"
  else
    HEXSTRIKE_API_TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  export HEXSTRIKE_API_TOKEN
  log "[auth] HEXSTRIKE_API_TOKEN not provided; generated an ephemeral token:"
  log "[auth]     ${HEXSTRIKE_API_TOKEN}"
  log "[auth] Set this as X-HexStrike-Token in your MCP client, or pin your own via docker/.env."
else
  export HEXSTRIKE_API_TOKEN
  log "[auth] Using HEXSTRIKE_API_TOKEN from the environment."
fi
# Raw command/code execution stays opt-in (issue #124); pass through if provided.
export HEXSTRIKE_ALLOW_RAW_EXEC="${HEXSTRIKE_ALLOW_RAW_EXEC:-}"

# --- Start HexStrike MCP server ---
GUNICORN_BIN="/opt/hexstrike/venv/bin/gunicorn"
if [ ! -x "$GUNICORN_BIN" ]; then
  log_error "[server] gunicorn not found or not executable at ${GUNICORN_BIN}."
  exit 1
fi

log "[server] Starting HexStrike MCP server on 0.0.0.0:8888"
exec "$GUNICORN_BIN" \
  --bind 0.0.0.0:8888 \
  --workers 2 \
  --threads 8 \
  --timeout 3600 \
  --graceful-timeout 120 \
  --keep-alive 60 \
  "hexstrike_server:app"
