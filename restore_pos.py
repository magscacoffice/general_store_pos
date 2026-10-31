#!/usr/bin/env python3
"""
Lightweight bootstrap for Khan Baba General Store POS.

Clones only the Android/Flutter application source required for development.
It excludes caches, build outputs, old backups, the Flutter SDK, and Firebase
client configuration (google-services.json).

The repository currently contains a Flutter gitlink but no .gitmodules file.
This script deliberately does not initialize or download that gitlink. Use the
Flutter SDK already installed in the Codespace (or install Flutter separately).
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


def run(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(args))
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True)


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
            "--no-checkout", "--no-recurse-submodules",
            "--branch", BRANCH, REPO_URL, str(TARGET)
        ])
        run(["git", "sparse-checkout", "init", "--cone"], cwd=TARGET)
        run(["git", "sparse-checkout", "set", *SPARSE_PATHS], cwd=TARGET)
        run(["git", "checkout", BRANCH], cwd=TARGET)
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: Restore stopped (command exit code {exc.returncode}).")
        if exc.stdout:
            print(exc.stdout)
        if exc.stderr:
            print(exc.stderr)
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

    gitlink = subprocess.run(
        ["git", "ls-tree", "HEAD", "flutter"],
        cwd=TARGET, text=True, capture_output=True, check=True
    ).stdout.strip()
    has_gitmodules = (TARGET / ".gitmodules").is_file()

    print("\nRESTORE COMPLETE")
    print(f"Project folder: {TARGET.resolve()}")
    print(f"Branch: {BRANCH}")
    print("\nNext commands:")
    print(f"  cd {TARGET}")
    print("  flutter pub get")
    print("\nFlutter SDK:")
    print("  The Flutter SDK is intentionally not downloaded by this script.")
    print("  Use the Codespace Flutter SDK if available, for example: ./flutter/bin/flutter")
    if gitlink.startswith("160000 ") and not has_gitmodules:
        print("\nNOTICE: The repository has a Flutter gitlink but no .gitmodules file.")
        print("  The script did not initialize or download it. This is a repository")
        print("  configuration issue, not an application-source restore failure.")
    print("\nFirebase note:")
    print("  Do NOT reuse an old google-services.json.")
    print("  Download the configuration from your Khan Baba General Store Firebase project")
    print("  and place it at android/app/google-services.json when Firebase is configured.")
    print("\nNo APKs, Gradle caches, Flutter SDK, Flutter build outputs, .dart_tool,")
    print("or old .bak files were intentionally restored.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
