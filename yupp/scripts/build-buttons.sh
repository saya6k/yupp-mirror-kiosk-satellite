#!/bin/bash
# Builds buttons/yupp-buttons.c, static, for the mirror's system image.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$WORK/out/buttons"
cp "$HERE/buttons/yupp-buttons.c" "$WORK/out/buttons/"
printf '%s\n' 'apk add -q gcc musl-dev linux-headers >/dev/null' \
    'cd /w/out/buttons && gcc -static -O2 -Wall -o yupp-buttons yupp-buttons.c && strip yupp-buttons && ls -l yupp-buttons' \
    >"$WORK/out/buttons/inner.sh"
container run --rm -c 1 -m 512M --mount type=bind,source="$WORK",target=/w alpine:3.22 sh /w/out/buttons/inner.sh
