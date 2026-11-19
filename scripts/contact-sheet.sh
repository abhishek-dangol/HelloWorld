#!/bin/zsh
# Puts PNGs side by side with labels into one image. Usage: scripts/contact-sheet.sh out.png a.png b.png ...
OUT=$1; shift
H=$(mktemp -d)/sheet.html
N=$#
W=$(( N * 300 + 20 ))
{ echo "<html><body style='margin:0;background:#222;font:600 16px -apple-system;color:#eee;display:flex;gap:10px;padding:10px'>"
  for f in "$@"; do echo "<div><img src='file://$f' style='width:290px;border-radius:18px;display:block'><div style='margin-top:6px'>${f:t:r}</div></div>"; done
  echo "</body></html>"; } > $H
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 --window-size=$W,670 --virtual-time-budget=3000 --screenshot="$OUT" "file://$H" 2>/dev/null
