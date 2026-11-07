#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_path="$project_root/.myss-runtime"
data_path="$project_root/.myss-data"
download_path="$data_path/download"
archive_path="$download_path/wnja-2.1.tar.xz"
xml_path="$download_path/wnja/wnja-2.1.xml"

mkdir -p "$download_path"
if [ ! -x "$runtime_path/bin/python3" ]; then
    python3 -m venv "$runtime_path"
fi
"$runtime_path/bin/python3" -m pip install --upgrade pip
"$runtime_path/bin/python3" -m pip install "sentence-transformers>=3.4,<6" "transformers>=4.48,<6" numpy
if [ ! -f "$xml_path" ]; then
    curl -L --fail --show-error https://github.com/bond-lab/wnja/releases/download/v2.1/wnja-2.1.tar.xz -o "$archive_path"
    tar -xJf "$archive_path" -C "$download_path"
fi
"$runtime_path/bin/python3" "$project_root/Sources/myss/Backend/semantic_backend.py" build \
    --xml "$xml_path" --output "$data_path" --batch-size 128
printf '%s\n' "myss semantic search setup completed"
