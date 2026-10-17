#!/usr/bin/env bash
# Convert every room TMX in mapdata/rooms into a scene in scenes/rooms.
# Usage: mapdata/convert_all.sh
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(dirname "$script_dir")"
rooms_dir="$script_dir/rooms"
template="$script_dir/template.tscn"
output_dir="$project_root/scenes/rooms"

mkdir -p "$output_dir"

count=0
errors=0
for tmx in "$rooms_dir"/*.tmx; do
    room="$(basename "$tmx" .tmx)"
    if python3 "$script_dir/convert_tmx_to_tscn.py" "$tmx" "$template" "$output_dir/$room.tscn" --name "$room"; then
        count=$((count + 1))
    else
        errors=$((errors + 1))
        echo "FAILED: $tmx"
    fi
done

echo
if [ "$errors" -eq 0 ]; then
    echo "Converted $count room(s) into $output_dir"
else
    echo "Converted $count room(s), $errors error(s)." >&2
fi

exit "$errors"
