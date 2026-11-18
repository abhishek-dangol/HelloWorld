#!/bin/zsh
# Build CinematiCam and publish it as an install link the iPhone can open from anywhere (no cable, no shared Wi-Fi).
# Hosted on Vercel (project "cinematicam-install"). Only devices in the development profile can install it.
# Usage: scripts/ship-link.sh
set -e
cd "$(dirname "$0")/.."
SITE=build/link-site
DOMAIN_FILE=scripts/link-domain.txt
STAMP=$(TZ=America/Chicago date +%Y%m%d-%H%M%S)
LABEL=$(TZ=America/Chicago date "+%b %-d, %-I:%M %p")

rm -rf build/link-export build/link-archive.xcarchive
xcodebuild -project CinematiCam.xcodeproj -scheme CinematiCam -configuration Debug -destination 'generic/platform=iOS' \
  -archivePath build/link-archive.xcarchive -allowProvisioningUpdates archive > build-archive.log 2>&1 || true
grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" build-archive.log | sort -u | cut -c1-300
xcodebuild -exportArchive -archivePath build/link-archive.xcarchive -exportOptionsPlist scripts/ExportOptions-dev.plist \
  -exportPath build/link-export -allowProvisioningUpdates > build-export.log 2>&1 || true
grep -E "error|EXPORT (SUCCEEDED|FAILED)" build-export.log | sort -u | cut -c1-300
mv build-archive.log build-export.log build/
IPA=$(ls build/link-export/*.ipa 2>/dev/null | head -1)
[[ -f "$IPA" ]] || { echo "No app file was made."; exit 1; }

write_site() {  # $1 = https://domain
  mkdir -p $SITE
  find $SITE -name "CinematiCam-*.ipa" -delete
  cp "$IPA" "$SITE/CinematiCam-$STAMP.ipa"
  cat > $SITE/manifest.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array><dict><key>kind</key><string>software-package</string>
<key>url</key><string>$1/CinematiCam-$STAMP.ipa</string></dict></array>
<key>metadata</key><dict><key>bundle-identifier</key><string>com.abhishekdangol.CinematiCam</string>
<key>bundle-version</key><string>1.0</string><key>kind</key><string>software</string>
<key>title</key><string>CinematiCam</string></dict></dict></array></dict></plist>
PLIST
  cat > $SITE/index.html <<HTML
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CinematiCam test build</title><meta name="robots" content="noindex">
<style>body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;
background:#0b0b0c;color:#fff;font-family:-apple-system,sans-serif;text-align:center;padding:24px}
a{background:#FFD60A;color:#000;text-decoration:none;font-weight:700;font-size:20px;padding:18px 34px;border-radius:30px}
p{color:rgba(255,255,255,.6);margin:0;line-height:1.5}</style></head><body>
<h1 style="margin:0;font-size:26px">CinematiCam test build</h1><p>Built $LABEL</p>
<a href="itms-services://?action=download-manifest&amp;url=$1/manifest.plist">Install</a>
<p>Tap Install, then Install again on the pop-up.</p></body></html>
HTML
  cat > $SITE/vercel.json <<JSON
{"headers":[{"source":"/(.*)","headers":[{"key":"Cache-Control","value":"no-store"}]}]}
JSON
}

deploy() { (cd $SITE && vercel deploy --prod --yes --name cinematicam-install 2>&1) > build/link-deploy.log; }

if [[ ! -s $DOMAIN_FILE ]]; then
  write_site "https://placeholder.invalid"
  deploy
  grep -oE "https://cinematicam-install[a-z0-9-]*\.vercel\.app" build/link-deploy.log | awk '{print length, $0}' | sort -n | head -1 | cut -d' ' -f2 > $DOMAIN_FILE
  [[ -s $DOMAIN_FILE ]] || { echo "Could not find the site address:"; cat build/link-deploy.log; exit 1; }
fi
DOMAIN=$(cat $DOMAIN_FILE)
write_site "$DOMAIN"
deploy
curl -sf "$DOMAIN/manifest.plist" | grep -q "CinematiCam-$STAMP.ipa" || { echo "The site isn't serving the new build yet."; cat build/link-deploy.log | tail -5; exit 1; }
echo "Install link: $DOMAIN  (built $LABEL)"
