#!/usr/bin/env bats
#
# extract-flowbar-strings.bats -- the build step that pulls the English UI
# string table out of the status renderer for the native Flow Bar plugin.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
EXTRACT="$SCRIPT_DIR/../scripts/extract-flowbar-strings.sh"

setup() {
	command -v node >/dev/null || skip 'node not installed'
	TEST_TMP=$(mktemp -d)
	export TEST_TMP
}

teardown() {
	[[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# A fake renderer: one non-English module, then the English one (with the
# JS-literal escapes a minifier emits), then unrelated code.
write_fixture() {
	node -e '
const keys={};for(let i=0;i<120;i++)keys["k"+i]="v"+i;
keys.new_mic_detected_body="Would you like to use this mic for Flow?";
keys.new_mic_detected_title="{{name}} detected";
keys.quote_test="it\x27s \"quoted\"";
const en=JSON.stringify(keys).replace(/\\/g,"\\\\").replace(/\x27/g,"\\\x27");
const de=JSON.stringify({new_mic_detected_body:"Willst du dieses Mikro benutzen?"}).replace(/\x27/g,"\\\x27");
process.stdout.write("6(e){\"use strict\";e.exports=JSON.parse(\x27"+de+"\x27)},7(e){\"use strict\";e.exports=JSON.parse(\x27"+en+"\x27)},8(e){e.exports=1}");
' > "$TEST_TMP/status.js"
}

@test "extract: writes the English table as JSON" {
	write_fixture
	run bash "$EXTRACT" "$TEST_TMP/status.js" "$TEST_TMP/out.json"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'OK: 123 English strings'* ]]
	run node -e 'const t=require(process.argv[1]);if(t.new_mic_detected_title!=="{{name}} detected")process.exit(1);if(t.quote_test!=="it\x27s \"quoted\"")process.exit(2);if(t.k5!=="v5")process.exit(3);' "$TEST_TMP/out.json"
	[[ "$status" -eq 0 ]]
}

@test "extract: fails loudly when the English marker is absent" {
	printf '%s' 'e.exports=JSON.parse(\x27{"a":"b"}\x27)' > "$TEST_TMP/status.js"
	run bash "$EXTRACT" "$TEST_TMP/status.js" "$TEST_TMP/out.json"
	[[ "$status" -ne 0 ]]
	[[ ! -f "$TEST_TMP/out.json" ]]
}

@test "extract: usage error without arguments" {
	run bash "$EXTRACT"
	[[ "$status" -eq 2 ]]
}
