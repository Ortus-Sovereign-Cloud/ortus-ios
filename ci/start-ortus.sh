#!/usr/bin/env bash
# Starts the Ortus program given on a fresh data directory, makes the
# owner, adds Iryna by invitation, and exports ORTUS_SERVER and ORTUS_CODE
# (her invitation code) for the phone tests ($GITHUB_ENV when in Actions).
set -euo pipefail
binary="$1"
port=8090
data="$(mktemp -d)"
token="$(openssl rand -hex 16)"
export ORTUS_ROLES=all ORTUS_DATA_DIR="$data" ORTUS_WEB_IP=127.0.0.1 ORTUS_WEB_PORT=$port \
  ORTUS_PUBLIC_URL="http://127.0.0.1:$port" ORTUS_SETUP_TOKEN="$token" \
  ORTUS_SMTP_LISTEN=127.0.0.1:2525 ORTUS_SUBMISSION_LISTEN=127.0.0.1:2587 ORTUS_IMAP_LISTEN=127.0.0.1:2143 \
  ORTUS_MEDIA_LISTEN=127.0.0.1:0 ORTUS_MAIL_HOSTNAME=mail.ministry.example
nohup "$binary" serve > "$data/ortus.log" 2>&1 &
for _ in $(seq 1 60); do curl -fs "http://127.0.0.1:$port/api/v1/health" > /dev/null && break; sleep 1; done
api() { curl -fsS -H 'Content-Type: application/json' -H 'X-Requested-With: ortus' "$@"; }
owner="$(api -X POST "http://127.0.0.1:$port/api/v1/setup" -d "{\"token\":\"$token\",\"name\":\"Taras Bondar\",\"email\":\"taras@ministry.example\"}")"
session="$(printf '%s' "$owner" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_token"])')"
invited="$(api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/admin/users" -d '{"email":"iryna@ministry.example","name":"Iryna Melnyk"}')"
code="$(printf '%s' "$invited" | python3 -c 'import json,sys; print(json.load(sys.stdin)["link"].split("#")[-1])')"
# Mail for Iryna: the domain, then a message from Anna, as another server
# would hand it over.
api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/mail/admin/domains" -d '{"domain":"ministry.example"}' > /dev/null
python3 - <<'MAIL'
import smtplib
message = """From: Anna Kowalska <anna@regional.example>\r
To: iryna@ministry.example\r
Subject: Gauge report and updated shelter agreement\r
Message-ID: <gauge-1@regional.example>\r
\r
Attached is today's gauge report and the updated shelter agreement.\r
"""
with smtplib.SMTP("127.0.0.1", 2525) as s:
    s.sendmail("anna@regional.example", ["iryna@ministry.example"], message)
MAIL
echo "ortus: running at http://127.0.0.1:$port; Iryna's code is ready"
if [ -n "${GITHUB_ENV:-}" ]; then
  { echo "ORTUS_SERVER=http://127.0.0.1:$port"; echo "ORTUS_CODE=$code"; } >> "$GITHUB_ENV"
else
  echo "export ORTUS_SERVER=http://127.0.0.1:$port ORTUS_CODE=$code"
fi
