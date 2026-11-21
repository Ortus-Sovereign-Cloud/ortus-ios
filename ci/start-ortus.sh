#!/usr/bin/env bash
# Starts the Ortus program given on a fresh data directory, makes the
# owner, adds Iryna by invitation, and exports ORTUS_SERVER and ORTUS_CODE
# (her invitation code) for the phone tests ($GITHUB_ENV when in Actions).
set -euo pipefail
binary="$1"
free() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
port=$(free) smtp=$(free) submission=$(free) imap=$(free) imaps=$(free) submissions=$(free)
data="$(mktemp -d)"
# Mail over TLS with a certificate of its own, which the importer trusts:
# this installation also plays the old mail server for S2.4.
# (A small CA and the server's certificate from it: a CA certificate is
# not taken as a server's own.)
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$data/ca.key" -out "$data/ca.crt" -days 2 -subj /CN=test-ca 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout "$data/tls.key" -out "$data/tls.csr" -subj /CN=old-server 2>/dev/null
printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > "$data/tls.ext"
openssl x509 -req -in "$data/tls.csr" -CA "$data/ca.crt" -CAkey "$data/ca.key" -CAcreateserial -days 2 -extfile "$data/tls.ext" -out "$data/tls.crt" 2>/dev/null
token="$(openssl rand -hex 16)"
export ORTUS_ROLES=all ORTUS_DATA_DIR="$data" ORTUS_WEB_IP=127.0.0.1 ORTUS_WEB_PORT=$port \
  ORTUS_PUBLIC_URL="http://127.0.0.1:$port" ORTUS_SETUP_TOKEN="$token" \
  ORTUS_SMTP_LISTEN=127.0.0.1:$smtp ORTUS_SUBMISSION_LISTEN=127.0.0.1:$submission ORTUS_IMAP_LISTEN=127.0.0.1:$imap \
  ORTUS_MEDIA_LISTEN=127.0.0.1:0 ORTUS_MAIL_HOSTNAME=mail.ministry.example \
  ORTUS_MAIL_TLS_CERT="$data/tls.crt" ORTUS_MAIL_TLS_KEY="$data/tls.key" ORTUS_IMPORT_CA="$data/ca.crt" \
  ORTUS_IMAPS_LISTEN=127.0.0.1:$imaps ORTUS_SUBMISSIONS_LISTEN=127.0.0.1:$submissions
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
# The old mailboxes (Olha's and Petro's, with mail), signed in by app
# passwords; the import starts with the passwords Taras was given: wrong.
passwords=""
for who in olha petro; do
  link="$(api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/admin/users" -d "{\"email\":\"$who.old@ministry.example\",\"name\":\"$who (old)\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["link"].split("#")[-1])')"
  theirs="$(api -X POST "http://127.0.0.1:$port/api/v1/invitation/accept" -d "{\"token\":\"$link\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_token"])')"
  pw="$(api -X POST -H "Authorization: Bearer $theirs" "http://127.0.0.1:$port/api/v1/me/app-passwords" -d '{"name":"Migration"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"
  passwords="$passwords${passwords:+,}$who.old@ministry.example=$pw"
  SMTP_PORT=$smtp WHO=$who python3 - <<'OLD'
import os, smtplib
to = f"{os.environ['WHO']}.old@ministry.example"
with smtplib.SMTP("127.0.0.1", int(os.environ["SMTP_PORT"])) as s:
    s.sendmail("anna@regional.example", [to], f"From: Anna Kowalska <anna@regional.example>\r\nTo: {to}\r\nSubject: Shelter agreement 2025\r\nMessage-ID: <{to}.1@regional.example>\r\n\r\nClause 4 is signed.\r\n")
OLD
done
api -X POST -H "Authorization: Bearer $session" "http://127.0.0.1:$port/api/v1/mail/admin/imports" \
  -d "{\"host\":\"127.0.0.1\",\"port\":$imaps,\"security\":\"tls\",\"accounts\":[{\"login\":\"olha.old@ministry.example\",\"password\":\"not-it\",\"to\":\"iryna@ministry.example\"},{\"login\":\"petro.old@ministry.example\",\"password\":\"not-it-either\",\"to\":\"taras@ministry.example\"}]}" > /dev/null
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
  { echo "ORTUS_SERVER=http://127.0.0.1:$port"; echo "ORTUS_CODE=$code"; echo "ORTUS_ADMIN_CODE=$admin"; echo "ORTUS_OWNER_TOTP=$totp"; echo "ORTUS_IMPORT_PASSWORDS=$passwords"; } >> "$GITHUB_ENV"
else
  echo "export ORTUS_SERVER=http://127.0.0.1:$port ORTUS_CODE=$code ORTUS_ADMIN_CODE=$admin ORTUS_OWNER_TOTP=$totp ORTUS_IMPORT_PASSWORDS=$passwords"
fi
