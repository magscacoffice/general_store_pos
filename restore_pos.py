#!/usr/bin/env python3
"""
Lightweight bootstrap for Khan Baba General Store POS.
Clones only the Android/Flutter source required to continue development.
It intentionally excludes caches, build outputs, old backups and Firebase
client configuration (google-services.json), which must come from the user's
own Firebase project.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO_URL = "https://github.com/magscacoffice/general_store_pos.git"
BRANCH = "feature/stock-profit-khata-backup"
TARGET = Path("general_store_pos")

SPARSE_PATHS = [
    ".github/workflows",
    ".gitignore",
    ".metadata",
    "README.md",
    "analysis_options.yaml",
    "pubspec.yaml",
    "pubspec.lock",
    "lib",
    "test",
    "android/app/build.gradle.kts",
    "android/app/src",
    "android/build.gradle.kts",
    "android/gradle",
    "android/gradle.properties",
    "android/settings.gradle.kts",
    "firestore.rules",
]


def run(args: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(args))
    subprocess.run(args, cwd=cwd, check=True)


def main() -> int:
    if shutil.which("git") is None:
        print("ERROR: Git is not installed in this Codespace.")
        return 1
    if TARGET.exists():
        print(f"ERROR: {TARGET} already exists. Script will not overwrite it.")
        print("Run this script from a clean/empty parent folder, or rename that folder first.")
        return 2

    try:
        run([
            "git", "clone", "--depth", "1", "--filter=blob:none",
            "--no-checkout", "--branch", BRANCH, REPO_URL, str(TARGET)
        ])
        run(["git", "sparse-checkout", "init", "--cone"], cwd=TARGET)
        run(["git", "sparse-checkout", "set", *SPARSE_PATHS], cwd=TARGET)
        run(["git", "checkout", BRANCH], cwd=TARGET)
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: Restore stopped (command exit code {exc.returncode}).")
        print("The partial folder, if created, has been left in place for inspection.")
        return exc.returncode or 1

    required = [
        TARGET / "pubspec.yaml",
        TARGET / "lib/main.dart",
        TARGET / "lib/db_helper.dart",
        TARGET / "android/app/build.gradle.kts",
    ]
    missing = [str(p) for p in required if not p.is_file()]
    if missing:
        print("ERROR: Required source files are missing:")
        print("\n".join(missing))
        return 3

    print("\nRESTORE COMPLETE")
    print(f"Project folder: {TARGET.resolve()}")
    print(f"Branch: {BRANCH}")
    print("\nNext commands:")
    print(f"  cd {TARGET}")
    print("  flutter pub get")
    print("\nFirebase note:")
    print("  Do NOT reuse the repository's old google-services.json.")
    print("  Download the new file from your Khan Baba General Store Firebase project")
    print("  and place it at android/app/google-services.json when we configure Firebase.")
    print("\nNo APKs, Gradle caches, Flutter build outputs, .dart_tool, or old .bak files were restored.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
