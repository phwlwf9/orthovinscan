#!/usr/bin/env python3
"""Package portable source only; never include caches, credentials or APKs."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
destination = root / "release" / "OrthoAI-Flutter-source.zip"
destination.parent.mkdir(exist_ok=True)
folders = {"android", "ios", "assets", "lib", "test", "integration_test", "docs", ".github", "scripts"}
root_files = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "README.md", ".gitignore"}
excluded_parts = {".gradle", "build", "Pods", ".symlinks", "ephemeral", "xcuserdata", "__pycache__"}
excluded_names = {"local.properties", "key.properties", "Generated.xcconfig", "flutter_export_environment.sh", "GeneratedPluginRegistrant.h", "GeneratedPluginRegistrant.m", "GeneratedPluginRegistrant.java"}
count = 0
with ZipFile(destination, "w", ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if not path.is_file() or path.is_symlink():
            continue
        if len(relative.parts) == 1:
            if path.name not in root_files:
                continue
        elif relative.parts[0] not in folders:
            continue
        if excluded_parts.intersection(relative.parts) or path.name in excluded_names:
            continue
        if path.suffix.lower() in {".jks", ".keystore", ".p12", ".mobileprovision", ".xcuserstate"}:
            continue
        archive.write(path, Path("orthoai") / relative)
        count += 1
print(f"{destination}: {count} files, {destination.stat().st_size} bytes")
