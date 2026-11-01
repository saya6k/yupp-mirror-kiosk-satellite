#!/bin/bash
# Fetches LineageOS's prebuilt Chromium WebView for arm64 to out/webview/,
# the one upstream's Echo Shows ship (manifest/lock.xml pins its revision for
# arm). The APK is in Git LFS on LineageOS's Gerrit.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
REPO=LineageOS/android_external_chromium-webview_prebuilt_arm64
REV="${1:-$(gh api "repos/$REPO/commits/main" --jq .sha)}"
mkdir -p "$WORK/out/webview"
ptr=$(curl -fsSL "https://raw.githubusercontent.com/$REPO/$REV/webview.apk")
oid=$(echo "$ptr" | sed -n 's/^oid sha256://p') size=$(echo "$ptr" | sed -n 's/^size //p')
# The download link the LFS server hands out lasts a minute.
url=$(curl -fsS -X POST -H 'Accept: application/vnd.git-lfs+json' -H 'Content-Type: application/vnd.git-lfs+json' \
    -d "{\"operation\":\"download\",\"transfers\":[\"basic\"],\"objects\":[{\"oid\":\"$oid\",\"size\":$size}]}" \
    "https://review.lineageos.org/$REPO.git/info/lfs/objects/batch" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["objects"][0]["actions"]["download"]["href"])')
curl -fsS -o "$WORK/out/webview/webview.apk" "$url"
[ "$(shasum -a 256 "$WORK/out/webview/webview.apk" | cut -c1-64)" = "$oid" ] || { echo "sha256 does not match" >&2; exit 1; }
echo "$REV" >"$WORK/out/webview/revision"
echo "webview.apk from $REPO@$REV"
