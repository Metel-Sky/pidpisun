#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-1.0.0}"
DIST="$ROOT/dist"
APP_NAME="podpisun"
DISPLAY_NAME="Підписун"
ENGINE_VENV="$ROOT/engine/.venv"
PY="${ENGINE_VENV}/bin/python3"
APP_SRC="$ROOT/build/macos/Build/Products/Release/${APP_NAME}.app"
STAGE="$DIST/macos-stage"
DMG="$DIST/${DISPLAY_NAME}-${VERSION}-macos.dmg"

echo "==> Python engine (PyInstaller)"
if [[ ! -x "$PY" ]]; then
  python3 -m venv "$ENGINE_VENV"
  PY="${ENGINE_VENV}/bin/python3"
fi
"$PY" -m pip install -q --upgrade pip
"$PY" -m pip install -q -r "$ROOT/engine/requirements.txt" pyinstaller
rm -rf "$ROOT/engine/build" "$ROOT/engine/dist"
"$PY" -m PyInstaller --noconfirm --clean \
  --workpath "$ROOT/engine/build" \
  --distpath "$ROOT/engine/dist" \
  "$ROOT/installer/podpisun_engine.spec"

echo "==> Flutter macOS release"
rm -rf "$APP_SRC/Contents/MacOS/podpisun_engine"
flutter build macos --release

if [[ ! -d "$APP_SRC" ]]; then
  echo "Не знайдено $APP_SRC" >&2
  exit 1
fi

echo "==> Bundle engine into .app"
ENGINE_DEST="$APP_SRC/Contents/MacOS/podpisun_engine"
rm -rf "$ENGINE_DEST"
cp -R "$ROOT/engine/dist/podpisun_engine" "$ENGINE_DEST"
chmod +x "$ENGINE_DEST/podpisun_engine"

echo "==> Ad-hoc codesign"
codesign --force --sign - "$ENGINE_DEST/podpisun_engine" >/dev/null || true
codesign --force --sign - "$APP_SRC/Contents/MacOS/${APP_NAME}" >/dev/null || true
codesign --force --sign - "$APP_SRC" >/dev/null || true

echo "==> DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_SRC" "$STAGE/${DISPLAY_NAME}.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "Готово: $DMG"
ls -lh "$DMG"
