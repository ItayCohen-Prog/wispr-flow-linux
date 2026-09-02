#!/usr/bin/env bash
#===============================================================================
# extract-flowbar-strings.sh -- pull the English UI string table out of the
# Wispr Flow status renderer so the native Flow Bar plugin can render
# notification titles/bodies/actions that main sends as i18n `{key}` objects.
#
# The renderer ships each language as a webpack module of the form
#   NNN(e){"use strict";e.exports=JSON.parse('{...}')}
# We locate the English one by a known English value, decode the JS string
# literal, and write the parsed object as JSON next to app.asar. The data
# stays inside the packaged app (it is Wispr's, not ours); only this script
# lives in the repo.
#
# Usage: extract-flowbar-strings.sh <status-renderer-index.js> <out.json>
#===============================================================================
set -uo pipefail

src="${1:-}"
out="${2:-}"
if [[ -z $src || -z $out || ! -f $src ]]; then
	echo "usage: $0 <status-renderer-index.js> <out.json>" >&2
	exit 2
fi

if ! command -v node >/dev/null; then
	echo 'ERROR: node is required to decode the string table.' >&2
	exit 1
fi

node - "$src" "$out" <<'NODE' || exit 1
const fs = require("fs");
const [src, out] = process.argv.slice(2);
const s = fs.readFileSync(src, "utf8");
const needle = '"new_mic_detected_body":"Would you like to use this mic for Flow?"';
const at = s.indexOf(needle);
if (at < 0) { console.error("ERROR: English marker string not found; re-audit the status renderer."); process.exit(1); }
const open = s.lastIndexOf("JSON.parse('", at);
if (open < 0) { console.error("ERROR: JSON.parse('...') wrapper not found before the marker."); process.exit(1); }
const start = open + "JSON.parse('".length;
// Find the closing quote of the JS string literal (skip escaped characters).
let i = start;
for (; i < s.length; i++) { const c = s[i]; if (c === "\\") { i++; continue; } if (c === "'") break; }
if (i >= s.length) { console.error("ERROR: unterminated string literal."); process.exit(1); }
const literal = s.slice(start, i);
// Decode the JS single-quoted literal without eval: handle the escapes a
// minifier emits (\', \\, \n, \uXXXX, \xXX); anything else passes through.
const decoded = literal.replace(/\\(u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)/g, (m, e) => {
  if (e[0] === "u") return String.fromCharCode(parseInt(e.slice(1), 16));
  if (e[0] === "x") return String.fromCharCode(parseInt(e.slice(1), 16));
  return { n: "\n", r: "\r", t: "\t", b: "\b", f: "\f", v: "\v", "0": "\0" }[e] ?? e;
});
let table;
try { table = JSON.parse(decoded); } catch (e) { console.error("ERROR: decoded table is not JSON: " + e.message); process.exit(1); }
const keys = Object.keys(table);
if (keys.length < 100 || typeof table.new_mic_detected_body !== "string") { console.error("ERROR: table looks wrong (" + keys.length + " keys)."); process.exit(1); }
fs.writeFileSync(out, JSON.stringify(table));
console.log("OK: " + keys.length + " English strings -> " + out);
NODE
