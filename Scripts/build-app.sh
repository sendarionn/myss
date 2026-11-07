#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=release
output_root="$project_root/dist"
app_path="$output_root/myss.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
cd "$project_root"
swift build -c "$configuration" --product myss
bin_path=$(swift build -c "$configuration" --show-bin-path)

rm -rf "$app_path"
mkdir -p "$macos_path" "$resources_path"
cp "$bin_path/myss" "$macos_path/myss"
cp "$project_root/App/Info.plist" "$contents_path/Info.plist"

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

install=false
restart=false
for argument in "$@"; do
    case "$argument" in
        --install) install=true ;;
        --restart) restart=true ;;
        *) printf '%s\n' "unknown option: $argument" >&2; exit 2 ;;
    esac
done

launch_path="$app_path"
if [ "$install" = true ]; then
    install_root="$HOME/Applications"
    mkdir -p "$install_root"
    rm -rf "$install_root/myss.app"
    cp -R "$app_path" "$install_root/myss.app"
    launch_path="$install_root/myss.app"
fi
printf '%s\n' "$launch_path"

if [ "$restart" = true ]; then
    # 新しいappの配置が終わってから旧プロセスを終了し、新しいappを起動する
    if pgrep -x myss >/dev/null; then
        killall myss 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            pgrep -x myss >/dev/null || break
            sleep 0.1
        done
    fi
    open "$launch_path"
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        if pid=$(pgrep -f "$launch_path/Contents/MacOS/myss"); then
            printf '%s\n' "restarted: pid $pid"
            break
        fi
        sleep 0.1
    done
fi
