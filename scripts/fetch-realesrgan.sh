#!/bin/bash
# Скачивает Real-ESRGAN (ncnn-vulkan, macOS) и модели в Resources/realesrgan.
# Архив проверяется по SHA-256; повторный запуск ничего не делает, если всё уже на месте.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=Resources/realesrgan
URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
SHA256="e0ad05580abfeb25f8d8fb55aaf7bedf552c375b5b4d9bd3c8d59764d2cc333a"
LICENSE_URL="https://raw.githubusercontent.com/xinntao/Real-ESRGAN-ncnn-vulkan/v0.2.0/LICENSE"

[ -x "$DEST/realesrgan-ncnn-vulkan" ] && [ -f "$DEST/models/realesrgan-x4plus.bin" ] && exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "→ скачиваю Real-ESRGAN (~52 МБ)"
curl -fL --progress-bar -o "$tmp/r.zip" "$URL"
echo "$SHA256  $tmp/r.zip" | shasum -a 256 -c - >/dev/null || { echo "✘ контрольная сумма не совпала" >&2; exit 1; }

unzip -q "$tmp/r.zip" 'realesrgan-ncnn-vulkan' 'models/realesrgan-x4plus*' -d "$tmp/x"
mkdir -p "$DEST/models"
cp "$tmp/x/realesrgan-ncnn-vulkan" "$DEST/"
cp "$tmp"/x/models/* "$DEST/models/"
chmod +x "$DEST/realesrgan-ncnn-vulkan"
codesign --force --sign - "$DEST/realesrgan-ncnn-vulkan" 2>/dev/null
curl -fsL -o "$DEST/LICENSE" "$LICENSE_URL" || true
echo "✔ $DEST"
