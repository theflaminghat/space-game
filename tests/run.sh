#!/usr/bin/env bash
# Run the headless test suite.
#
# Each test is a SceneTree script that loads the game, pokes it, and prints "FAILS: n".
# There is no test framework: Godot's own --script runner is the harness.
#
#   tests/run.sh              all tests
#   tests/run.sh regression   just the ones whose name contains "regression"
#
# GODOT may be set to point at a different binary.

set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/programs/Godot_4.7.2.x86_64}"
if ! [ -x "$GODOT" ]; then
	command -v godot >/dev/null && GODOT=$(command -v godot) || {
		echo "no Godot binary: set GODOT=/path/to/godot" >&2; exit 2; }
fi

# A test that errors out never reaches quit(), so it hangs rather than failing.
# The timeout is what turns that into a reportable result.
TIMEOUT="${TIMEOUT:-240}"

filter="${1:-}"
total=0; passed=0; broken=0
for t in tests/*.gd; do
	name=$(basename "$t" .gd)
	[ -n "$filter" ] && [[ "$name" != *"$filter"* ]] && continue
	total=$((total + 1))
	printf '%-22s ' "$name"
	out=$(timeout "$TIMEOUT" "$GODOT" --headless --path . --script "$t" 2>&1)
	rc=$?
	fails=$(printf '%s\n' "$out" | grep -oE 'FAILS: [0-9]+' | tail -1 | grep -oE '[0-9]+')
	if [ "$rc" = "124" ]; then
		echo "TIMEOUT (a script error aborts _run before quit — check the method names)"
		broken=$((broken + 1))
	elif [ -z "$fails" ]; then
		echo "NO RESULT"
		printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Nonexistent|Invalid' | head -3 | sed 's/^/    /'
		broken=$((broken + 1))
	elif [ "$fails" = "0" ]; then
		echo "ok"
		passed=$((passed + 1))
	else
		echo "$fails FAILED"
		printf '%s\n' "$out" | grep -E '^FAIL:' | head -8 | sed 's/^/    /'
	fi
done

echo "── $passed/$total ok${broken:+, $broken did not report}"
[ "$passed" = "$total" ]
