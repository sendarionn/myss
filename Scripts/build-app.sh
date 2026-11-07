#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=release
output_root="$project_root/dist"
app_path="$output_root/myss.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
prebuilt_path="$output_root/PrebuiltIndex"
archive_name="myss-semantic-index-v1.tar.gz"

if [ ! -f "$project_root/.myss-data/senses.json" ] || [ ! -f "$project_root/.myss-data/embeddings.npy" ]; then
    printf '%s\n' "prebuilt semantic index is missing; run the developer setup first" >&2
    exit 1
fi

/usr/bin/python3 "$project_root/Sources/myss/Backend/semantic_backend.py" finalize-metadata \
    --data "$project_root/.myss-data"
rm -rf "$prebuilt_path"
mkdir -p "$prebuilt_path/stage"
cp "$project_root/.myss-data/senses.json" "$prebuilt_path/stage/senses.json"
cp "$project_root/.myss-data/embeddings.npy" "$prebuilt_path/stage/embeddings.npy"
cp "$project_root/.myss-data/metadata.json" "$prebuilt_path/stage/metadata.json"
cp "$project_root/App/JAPANESE_WORDNET_LICENSE.txt" "$prebuilt_path/stage/JAPANESE_WORDNET_LICENSE.txt"
tar -czf "$prebuilt_path/$archive_name" -C "$prebuilt_path/stage" .
rm -rf "$prebuilt_path/stage"
archive_sha=$(shasum -a 256 "$prebuilt_path/$archive_name" | awk '{print $1}')
archive_size=$(stat -f '%z' "$prebuilt_path/$archive_name")
/usr/bin/python3 -c 'import json,sys; print(json.dumps({"indexVersion":"1","archive":sys.argv[1],"sha256":sys.argv[2],"size":int(sys.argv[3])}))' \
    "$archive_name" "$archive_sha" "$archive_size" > "$prebuilt_path/manifest.json"

cd "$project_root"
swift build -c "$configuration" --product myss
bin_path=$(swift build -c "$configuration" --show-bin-path)

rm -rf "$app_path"
mkdir -p "$macos_path" "$resources_path"
cp "$bin_path/myss" "$macos_path/myss"
cp -R "$bin_path/myss_myss.bundle" "$resources_path/myss_myss.bundle"
find "$resources_path/myss_myss.bundle" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$resources_path/myss_myss.bundle" -type f -name '*.pyc' -delete
cp "$project_root/App/Info.plist" "$contents_path/Info.plist"
cp -R "$prebuilt_path" "$resources_path/PrebuiltIndex"

icon_work=$(mktemp -d)
iconset="$icon_work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$project_root/App/AppIcon.svg" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -s format png -z "$double_size" "$double_size" "$project_root/App/AppIcon.svg" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources_path/AppIcon.icns"
rm -rf "$icon_work"

codesign --force --deep --sign - --entitlements "$project_root/App/myss.entitlements" "$app_path"

if [ "${1:-}" = "--install" ]; then
    install_root="$HOME/Applications"
    mkdir -p "$install_root"
    rm -rf "$install_root/myss.app"
    cp -R "$app_path" "$install_root/myss.app"
    printf '%s\n' "$install_root/myss.app"
else
    printf '%s\n' "$app_path"
fi
