#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-1.0.0}"
DIST="$ROOT/dist"
APP_NAME="podpisun"
DISPLAY_NAME="Підписун"
VAULT_NAME="pechatky.podpisun"
ENGINE_VENV="$ROOT/engine/.venv"
PY="${ENGINE_VENV}/bin/python3"
APP_SRC="$ROOT/build/macos/Build/Products/Release/${APP_NAME}.app"
ENGINE_DIST="$ROOT/engine/dist/podpisun_engine"
PORTABLE="$DIST/${DISPLAY_NAME}-${VERSION}-macos-portable"
ZIP="$DIST/${DISPLAY_NAME}-${VERSION}-macos-portable.zip"

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
# Sidecar from a previous package must not sit inside .app during Xcode codesign.
rm -rf "$APP_SRC/Contents/MacOS/podpisun_engine"
flutter build macos --release

if [[ ! -d "$APP_SRC" ]]; then
  echo "Не знайдено $APP_SRC" >&2
  exit 1
fi

echo "==> Bundle engine into .app"
ENGINE_DEST="$APP_SRC/Contents/MacOS/podpisun_engine"
rm -rf "$ENGINE_DEST"
cp -R "$ENGINE_DIST" "$ENGINE_DEST"
chmod +x "$ENGINE_DEST/podpisun_engine"

echo "==> Stamp vault 250 MB inside the .app"
VAULT="$APP_SRC/Contents/MacOS/$VAULT_NAME"
IMPORT_ARGS=()
if [[ -d "$ROOT/portable_data/PNG" ]]; then
  IMPORT_ARGS+=(--import-dir "$ROOT/portable_data/PNG")
fi
if [[ -d "$APP_SRC/Contents/MacOS/PNG" ]]; then
  IMPORT_ARGS+=(--import-dir "$APP_SRC/Contents/MacOS/PNG")
fi
dart run tool/init_stamp_vault.dart "$VAULT" ${IMPORT_ARGS[@]+"${IMPORT_ARGS[@]}"}
rm -rf "$APP_SRC/Contents/MacOS/PNG"

echo "==> Ad-hoc codesign"
codesign --force --sign - "$ENGINE_DEST/podpisun_engine" >/dev/null || true
codesign --force --sign - "$APP_SRC/Contents/MacOS/${APP_NAME}" >/dev/null || true
codesign --force --sign - "$APP_SRC" >/dev/null || true

echo "==> Portable folder"
mkdir -p "$DIST"
rm -rf "$PORTABLE" "$ZIP"
mkdir -p "$PORTABLE"
cp -R "$APP_SRC" "$PORTABLE/${DISPLAY_NAME}.app"

cat > "$PORTABLE/ЧИТАЙМЕНЕ.txt" <<'EOF'
Підписун — портативна версія

Скопіюйте файл Підписун.app на флешку або інший комп’ютер.
Усі печатки лежать всередині програми, в одному файлі pechatky.podpisun
на 250 МБ. Окрему папку PNG копіювати не треба.

Якщо на іншому комп’ютері Підписун уже стоїть — достатньо скопіювати
лише pechatky.podpisun (з Contents/MacOS/) і покласти його поруч
із програмою.

Додавайте PNG кнопкою «Додати PNG» або перетягуванням у ліву панель.
EOF

ditto -c -k --sequesterRsrc --keepParent "$PORTABLE" "$ZIP"

echo "Готово: $PORTABLE"
echo "Архів:  $ZIP"
ls -lh "$ZIP"
ls -lh "$PORTABLE"
