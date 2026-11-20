#!/usr/bin/env bash
# App Store 프리뷰 이미지 렌더 — headless Chrome으로 screenshots.html을 찍는다.
# 출력: design/appstore/export/{6.9,6.5}/N.jpg  (알파 없는 sRGB JPEG, App Store 규격)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SLIDES="${SLIDES:-1 2 3 4 5 6 7}"
render() { # $1=label $2=css-width $3=css-height
  local out="export/$1"; mkdir -p "$out"
  for s in $SLIDES; do
    local png; png="$(mktemp -t pingshot).png"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --force-device-scale-factor=3 --window-size="$2,$3" --virtual-time-budget=2000 \
      --screenshot="$png" "file://$PWD/screenshots.html?s=$s&w=$2&h=$3" >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 95 "$png" --out "$out/$s.jpg" >/dev/null
    rm -f "$png"
    echo "$out/$s.jpg $(sips -g pixelWidth -g pixelHeight "$out/$s.jpg" | awk '/pixel/{printf $2" "}')"
  done
}
render 6.9 440 956   # 1320x2868 (APP_IPHONE_67 / 6.9")
render 6.5 414 896   # 1242x2688 (APP_IPHONE_65)
