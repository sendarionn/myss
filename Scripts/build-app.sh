#!/bin/sh
set -eu

# 使い方: Scripts/build-app.sh [--install] [--restart] [--adhoc]
# myssはAccessibility権限を使うため、通常は固定のcodesigning identityで署名する
# identityはMYSS_CODESIGN_IDENTITY、未設定ならKeychain内の唯一のApple Development identityを使う

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=release
output_root="$project_root/dist"
app_path="$output_root/myss.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

install=false
restart=false
adhoc=false
for argument in "$@"; do
    case "$argument" in
        --install) install=true ;;
        --restart) restart=true ;;
        --adhoc) adhoc=true ;;
        *) printf '%s\n' "unknown option: $argument" >&2; exit 2 ;;
    esac
done

# ビルド前に署名identityを決める　見つからなければad-hoc署名へ黙って戻さず終了する
if [ "$adhoc" = true ]; then
    codesign_identity="-"
    identity_label="ad-hoc（Accessibility権限は再ビルドごとに外れる可能性があります）"
elif [ -n "${MYSS_CODESIGN_IDENTITY:-}" ]; then
    codesign_identity="$MYSS_CODESIGN_IDENTITY"
    identity_label="$MYSS_CODESIGN_IDENTITY"
else
    identities=$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9][0-9]*) \([0-9A-F]\{40\}\) "\(Apple Development: .*\)"$/\1 \2/p')
    identity_count=$(printf '%s' "$identities" | grep -c . || true)
    if [ "$identity_count" -eq 0 ]; then
        printf '%s\n' "利用可能なcodesigning identityがありません" \
            "Apple Development証明書をKeychainへ追加するか、MYSS_CODESIGN_IDENTITYを設定してください" >&2
        exit 1
    fi
    if [ "$identity_count" -gt 1 ]; then
        printf '%s\n' "複数のcodesigning identityが見つかりました" "MYSS_CODESIGN_IDENTITYを設定してください" >&2
        printf '%s\n' "$identities" | sed 's/^[0-9A-F]* /  /' >&2
        exit 1
    fi
    # 同名証明書があっても曖昧にならないよう、SHA-1で署名する
    codesign_identity=${identities%% *}
    identity_label=${identities#* }
fi

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
printf '%s\n' "Build: success"

codesign --force --deep --sign "$codesign_identity" \
    --entitlements "$project_root/App/myss.entitlements" "$app_path"
printf '%s\n' "Signing identity: $identity_label"
if ! codesign --verify --deep --strict "$app_path"; then
    printf '%s\n' "Code sign: invalid　インストールと再起動を中止しました" >&2
    exit 1
fi
printf '%s\n' "Code sign: valid"

launch_path="$app_path"
if [ "$install" = true ]; then
    install_root="$HOME/Applications"
    mkdir -p "$install_root"
    rm -rf "$install_root/myss.app"
    cp -R "$app_path" "$install_root/myss.app"
    launch_path="$install_root/myss.app"
    printf '%s\n' "Installed: $launch_path"
else
    printf '%s\n' "Output: $launch_path"
fi

if [ "$restart" = true ]; then
    # 新しいappの配置が終わってから旧プロセスを終了し、完全に終了してから新しいappを起動する
    if pgrep -x myss >/dev/null; then
        killall myss 2>/dev/null || true
        attempts=0
        while pgrep -x myss >/dev/null; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 50 ]; then
                printf '%s\n' "旧myssが終了しないため起動を中止しました" >&2
                exit 1
            fi
            sleep 0.1
        done
    fi
    open "$launch_path"
    attempts=0
    until pid=$(pgrep -f "$launch_path/Contents/MacOS/myss"); do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 50 ]; then
            printf '%s\n' "新しいmyssの起動を確認できませんでした" >&2
            exit 1
        fi
        sleep 0.1
    done
    printf '%s\n' "Restarted: PID $pid"
fi
printf '%s\n' "Accessibility permission: アプリ側で確認（設定 → 詳細 → 選択取得診断）"
