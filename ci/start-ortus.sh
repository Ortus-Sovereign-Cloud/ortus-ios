#!/usr/bin/env bash
# Starts the Ortus program given on a fresh data directory, makes the
# owner, adds Iryna by invitation, and exports ORTUS_SERVER and ORTUS_CODE
# (her invitation code) for the phone tests ($GITHUB_ENV when in Actions).
set -euo pipefail
binary="$1"
free() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
port=$(free) smtp=$(free) submission=$(free) imap=$(free)
data="$(mktemp -d)"
token="$(openssl rand -hex 16)"
export ORTUS_ROLES=all ORTUS_DATA_DIR="$data" ORTUS_WEB_IP=127.0.0.1 ORTUS_WEB_PORT=$port \
  ORTUS_PUBLIC_URL="http://127.0.0.1:$port" ORTUS_SETUP_TOKEN="$token" \
  ORTUS_SMTP_LISTEN=127.0.0.1:$smtp ORTUS_SUBMISSION_LISTEN=127.0.0.1:$submission ORTUS_IMAP_LISTEN=127.0.0.1:$imap \
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
SMTP_PORT=$smtp python3 - <<'MAIL'
import os, smtplib
message = """From: Anna Kowalska <anna@regional.example>\r
To: iryna@ministry.example\r
Subject: Gauge report and updated shelter agreement\r
Message-ID: <gauge-1@regional.example>\r
\r
Attached is today's gauge report and the updated shelter agreement.\r
"""
with smtplib.SMTP("127.0.0.1", int(os.environ["SMTP_PORT"])) as s:
    s.sendmail("anna@regional.example", ["iryna@ministry.example"], message)
MAIL
# S1.9: Taras sends a decision to Iryna to sign (a route with one signing step).
doc="$(api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/docs/documents" -d '{"parent":"","name":"Flood response plan 2026"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/drive/items/$doc/shares" -d '{"email":"iryna@ministry.example","role":"view"}' > /dev/null
api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/docs/documents/$doc/reviews" -d '{"steps":[{"email":"iryna@ministry.example","title":"Director signs","kind":"sign"}],"note":"Please sign today."}' > /dev/null
# S2.4: a mailbox import from an old server that does not answer (it
# fails), and an IT administrator who fixes it from the phone.
api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/mail/admin/imports" -d '{"host":"127.0.0.1","port":1,"security":"tls","accounts":[{"login":"iryna.old","password":"wrong","to":"iryna@ministry.example"}]}' > /dev/null
admin="$(api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/admin/users" -d '{"email":"oksana@ministry.example","name":"Oksana Lysenko","role":"admin"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["link"].split("#")[-1])')"
# The owner signs in with a password and an authenticator app as well
# (the phones' password sign-in): its secret goes to the tests.
api -X PUT -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/me/password" -d '{"password":"flood-plan-2026-ministry"}' > /dev/null
totp="$(api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/me/totp" | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])')"
now="$(python3 - "$totp" <<'TOTP'
import base64, hashlib, hmac, struct, sys, time
key = base64.b32decode(sys.argv[1].upper() + "=" * (-len(sys.argv[1]) % 8))
mac = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
o = mac[-1] & 15
print("%06d" % ((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 1000000))
TOTP
)"
api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/me/totp/confirm" -d "{\"code\":\"$now\"}" > /dev/null
echo "ortus: running at http://127.0.0.1:$port; Iryna's code is ready"
if [ -n "${GITHUB_ENV:-}" ]; then
  { echo "ORTUS_SERVER=http://127.0.0.1:$port"; echo "ORTUS_CODE=$code"; echo "ORTUS_ADMIN_CODE=$admin"; echo "ORTUS_OWNER_TOTP=$totp"; } >> "$GITHUB_ENV"
else
  echo "export ORTUS_SERVER=http://127.0.0.1:$port ORTUS_CODE=$code ORTUS_ADMIN_CODE=$admin ORTUS_OWNER_TOTP=$totp"
fi
