#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
if [[ -n "${ORTHOAI_TOOLCHAIN_ENV:-}" ]]; then
  source "$ORTHOAI_TOOLCHAIN_ENV"
fi

flutter pub get
flutter analyze
flutter test
flutter build apk --release

artifact="build/app/outputs/flutter-apk/app-release.apk"
test -s "$artifact"
mkdir -p release
cp "$artifact" release/OrthoAI-Android.apk
if command -v sha256sum >/dev/null 2>&1; then
  (cd release && sha256sum OrthoAI-Android.apk > OrthoAI-Android.apk.sha256)
else
  (cd release && shasum -a 256 OrthoAI-Android.apk > OrthoAI-Android.apk.sha256)
fi
wc -c < release/OrthoAI-Android.apk
cat release/OrthoAI-Android.apk.sha256
echo 'Created release/OrthoAI-Android.apk. Default signing is development/debug signing.'
