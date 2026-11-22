#!/usr/bin/env node
// Makes sign-in codes for App Review on a sample installation: three
// reviewer accounts (app.review1..3@<domain>), each with a fresh one-time
// invitation (7 days). A reviewer types the server and a code into the
// app's join screen, then makes the phone their key.
//
//   ORTUS_REVIEW_SERVER=https://sample.ortus.cc ORTUS_REVIEW_EMAIL=… \
//   ORTUS_REVIEW_PASSWORD=… ORTUS_REVIEW_TOTP_SECRET=… node store/ios/review-codes.mjs
//
// The owner's password and authenticator secret are the sample's (from
// tools/sample-org.mjs); nothing is written anywhere.
import { createHmac } from "node:crypto";

const server = (process.env.ORTUS_REVIEW_SERVER ?? "").replace(/\/$/, "");
const email = process.env.ORTUS_REVIEW_EMAIL;
const password = process.env.ORTUS_REVIEW_PASSWORD;
const secret = process.env.ORTUS_REVIEW_TOTP_SECRET;
if (!server || !email || !password || !secret) {
  console.error("set ORTUS_REVIEW_SERVER, ORTUS_REVIEW_EMAIL, ORTUS_REVIEW_PASSWORD and ORTUS_REVIEW_TOTP_SECRET");
  process.exit(2);
}

function totp(base32) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of base32.replace(/=+$/, "").toUpperCase()) bits += alphabet.indexOf(c).toString(2).padStart(5, "0");
  const key = Buffer.from(bits.match(/.{8}/g).map((b) => parseInt(b, 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30_000)));
  const mac = createHmac("sha1", key).update(counter).digest();
  const o = mac[19] & 15;
  return String((mac.readUInt32BE(o) & 0x7fffffff) % 1_000_000).padStart(6, "0");
}

async function api(method, path, body, token) {
  const headers = { "X-Requested-With": "ortus", "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const r = await fetch(`${server}/api/v1${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : {};
}

const { ticket } = await api("POST", "/session/password", { email, password });
const { session_token: session } = await api("POST", "/session/code", { ticket, code: totp(secret) });
const domain = new URL(server).hostname;
const people = (await api("GET", "/admin/users", undefined, session)).users;
console.log(`Server: ${domain}\n`);
for (const n of [1, 2, 3]) {
  const address = `app.review${n}@${domain}`;
  const existing = people.find((p) => p.email === address);
  let sent;
  if (!existing) {
    sent = await api("POST", "/admin/users", { email: address, name: `App Review ${n}`, send: false }, session);
  } else if (existing.state === "invited") {
    sent = await api("POST", `/admin/users/${existing.id}/invitation`, { send: false }, session);
  } else {
    // Joined before: start them again with a new invitation.
    sent = await api("POST", `/admin/users/${existing.id}/reset`, { send: false }, session);
  }
  console.log(`Code ${n}: ${new URL(sent.link).hash.slice(1)}  (valid until ${new Date(sent.expires_at).toISOString().slice(0, 10)})`);
}
await api("POST", "/session/sign-out", {}, session).catch(() => undefined);
