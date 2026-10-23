#!/usr/bin/env bash
# Regenerate the modelled meshes in models/ from their Blender build scripts.
#
# The .glb files ARE committed — nobody needs Blender to run or build the game.
# This only has to run when a model's script changes.
#
#   tools/build_models.sh
#
# BLENDER may be set to point at a different binary.  Note that a distro Blender
# packaged against the system Python often has no numpy, which the glTF exporter
# imports — if the export dies on "No module named 'numpy'", that is why, and an
# official build (which bundles its own Python) is the quickest way past it.

set -uo pipefail
cd "$(dirname "$0")/.."

BLENDER="${BLENDER:-blender}"
if ! command -v "$BLENDER" >/dev/null && ! [ -x "$BLENDER" ]; then
	echo "no Blender binary: set BLENDER=/path/to/blender" >&2; exit 2
fi

mkdir -p models
rc=0
for script in tools/[!_]*.py; do
	name=$(basename "$script" .py)
	out="$PWD/models/orbital_${name}.glb"
	printf '%-18s ' "$name"
	if log=$("$BLENDER" --background --factory-startup --python "$script" -- "$out" 2>&1); then
		printf '%s\n' "$log" | grep -oE '[A-Z]+_OK .*' || echo "built"
	else
		echo "FAILED"
		printf '%s\n' "$log" | grep -E 'Error|No module' | head -3 | sed 's/^/    /'
		rc=1
	fi
done
exit $rc
