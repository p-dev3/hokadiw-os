#!/usr/bin/env python3
"""Patch a pinned termux-app checkout for HOKADIW without renaming Java packages."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


JAVA_NAMESPACE = "com.termux"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected exactly one match in {path} but found {count}: {old!r}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_once_in_text(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one {label} match but found {count}: {old!r}")
    return text.replace(old, new, 1)


def patch_entity(text: str, entity: str, value: str, label: str) -> str:
    pattern = re.compile(rf'<!ENTITY\s+{re.escape(entity)}\s+"[^"]*">')
    text, count = pattern.subn(f'<!ENTITY {entity} "{value}">', text, count=1)
    if count != 1:
        raise SystemExit(f"Expected one {entity} entity in {label}, found {count}")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--package", required=True)
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--repo", required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    gradle = root / "app/build.gradle"
    app_strings = root / "app/src/main/res/values/strings.xml"
    shared_strings = root / "termux-shared/src/main/res/values/strings.xml"
    shortcuts = root / "app/src/main/res/xml/shortcuts.xml"
    constants = (
        root
        / "termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java"
    )

    required = [gradle, app_strings, shared_strings, shortcuts, constants]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing expected upstream files:\n" + "\n".join(missing))

    gradle_text = gradle.read_text(encoding="utf-8")
    gradle_text = replace_once_in_text(
        gradle_text,
        "    defaultConfig {\n        minSdkVersion",
        "    defaultConfig {\n"
        f'        applicationId "{args.package}"\n'
        "        minSdkVersion",
        "defaultConfig",
    )

    placeholder_values = {
        "TERMUX_PACKAGE_NAME": ("com.termux", args.package),
        "TERMUX_APP_NAME": ("Termux", args.app_name),
        "TERMUX_API_APP_NAME": ("Termux:API", "HOKADIW:API"),
        "TERMUX_BOOT_APP_NAME": ("Termux:Boot", "HOKADIW:Boot"),
        "TERMUX_FLOAT_APP_NAME": ("Termux:Float", "HOKADIW:Float"),
        "TERMUX_STYLING_APP_NAME": ("Termux:Styling", "HOKADIW:Styling"),
        "TERMUX_TASKER_APP_NAME": ("Termux:Tasker", "HOKADIW:Tasker"),
        "TERMUX_WIDGET_APP_NAME": ("Termux:Widget", "HOKADIW:Widget"),
    }
    for key, (old_value, new_value) in placeholder_values.items():
        gradle_text = replace_once_in_text(
            gradle_text,
            f'manifestPlaceholders.{key} = "{old_value}"',
            f'manifestPlaceholders.{key} = "{new_value}"',
            f"manifest placeholder {key}",
        )

    sdk_line = "        targetSdkVersion project.properties.targetSdkVersion.toInteger()\n"
    gradle_text = replace_once_in_text(
        gradle_text,
        sdk_line,
        sdk_line + "        ndk { abiFilters 'arm64-v8a' }\n",
        "targetSdkVersion",
    )

    task_start = gradle_text.find("task downloadBootstraps() {")
    task_end = gradle_text.find("\nafterEvaluate {", task_start)
    if task_start < 0 or task_end < 0:
        raise SystemExit("Could not locate the upstream downloadBootstraps task")
    local_bootstrap_task = """task downloadBootstraps() {
    doLast {
        def file = new File(projectDir, "src/main/cpp/bootstrap-aarch64.zip")
        if (!file.exists()) {
            throw new GradleException("Missing HOKADIW bootstrap: " + file)
        }
        logger.quiet("Using local HOKADIW bootstrap " + file)
    }
}
"""
    gradle_text = (
        gradle_text[:task_start] + local_bootstrap_task + gradle_text[task_end:]
    )
    gradle.write_text(gradle_text, encoding="utf-8")

    entity_values = {
        "TERMUX_PACKAGE_NAME": args.package,
        "TERMUX_APP_NAME": args.app_name,
        "TERMUX_API_APP_NAME": "HOKADIW:API",
        "TERMUX_BOOT_APP_NAME": "HOKADIW:Boot",
        "TERMUX_FLOAT_APP_NAME": "HOKADIW:Float",
        "TERMUX_STYLING_APP_NAME": "HOKADIW:Styling",
        "TERMUX_TASKER_APP_NAME": "HOKADIW:Tasker",
        "TERMUX_WIDGET_APP_NAME": "HOKADIW:Widget",
    }
    for path in (app_strings, shared_strings):
        text = path.read_text(encoding="utf-8")
        for entity, value in entity_values.items():
            text = patch_entity(text, entity, value, str(path))
        if path == shared_strings:
            text = patch_entity(
                text,
                "TERMUX_PREFIX_DIR_PATH",
                f"/data/data/{args.package}/files/usr",
                str(path),
            )
        path.write_text(text, encoding="utf-8")

    shortcuts_text = shortcuts.read_text(encoding="utf-8")
    target_count = shortcuts_text.count('android:targetPackage="com.termux"')
    if target_count < 1:
        raise SystemExit("No shortcut targetPackage entries were found")
    shortcuts_text = shortcuts_text.replace(
        'android:targetPackage="com.termux"',
        f'android:targetPackage="{args.package}"',
    )
    shortcuts_text = replace_once_in_text(
        shortcuts_text,
        'android:name="com.termux.app.failsafe_session"',
        f'android:name="{args.package}.app.failsafe_session"',
        "failsafe shortcut extra",
    )
    shortcuts.write_text(shortcuts_text, encoding="utf-8")

    constants_text = constants.read_text(encoding="utf-8")
    constants_replacements = {
        'public static final String TERMUX_APP_NAME = "Termux";':
            f'public static final String TERMUX_APP_NAME = "{args.app_name}";',
        'public static final String TERMUX_PACKAGE_NAME = "com.termux";':
            f'public static final String TERMUX_PACKAGE_NAME = "{args.package}";',
        'public static final String TERMUX_GITHUB_REPO_NAME = "termux-app";':
            f'public static final String TERMUX_GITHUB_REPO_NAME = "{args.repo}";',
        'public static final String TERMUX_GITHUB_REPO_URL = TERMUX_GITHUB_ORGANIZATION_URL + "/" + TERMUX_GITHUB_REPO_NAME;':
            f'public static final String TERMUX_GITHUB_REPO_URL = "https://github.com/{args.owner}/{args.repo}";',
        'public static final String BUILD_CONFIG_CLASS_NAME = TERMUX_PACKAGE_NAME + ".BuildConfig";':
            f'public static final String BUILD_CONFIG_CLASS_NAME = "{JAVA_NAMESPACE}.BuildConfig";',
        'public static final String FILE_SHARE_RECEIVER_ACTIVITY_CLASS_NAME = TERMUX_PACKAGE_NAME + ".app.api.file.FileShareReceiverActivity";':
            f'public static final String FILE_SHARE_RECEIVER_ACTIVITY_CLASS_NAME = "{JAVA_NAMESPACE}.app.api.file.FileShareReceiverActivity";',
        'public static final String FILE_VIEW_RECEIVER_ACTIVITY_CLASS_NAME = TERMUX_PACKAGE_NAME + ".app.api.file.FileViewReceiverActivity";':
            f'public static final String FILE_VIEW_RECEIVER_ACTIVITY_CLASS_NAME = "{JAVA_NAMESPACE}.app.api.file.FileViewReceiverActivity";',
        'public static final String TERMUX_ACTIVITY_NAME = TERMUX_PACKAGE_NAME + ".app.TermuxActivity";':
            f'public static final String TERMUX_ACTIVITY_NAME = "{JAVA_NAMESPACE}.app.TermuxActivity";',
        'public static final String TERMUX_SETTINGS_ACTIVITY_NAME = TERMUX_PACKAGE_NAME + ".app.activities.SettingsActivity";':
            f'public static final String TERMUX_SETTINGS_ACTIVITY_NAME = "{JAVA_NAMESPACE}.app.activities.SettingsActivity";',
        'public static final String TERMUX_SERVICE_NAME = TERMUX_PACKAGE_NAME + ".app.TermuxService";':
            f'public static final String TERMUX_SERVICE_NAME = "{JAVA_NAMESPACE}.app.TermuxService";',
        'public static final String RUN_COMMAND_SERVICE_NAME = TERMUX_PACKAGE_NAME + ".app.RunCommandService";':
            f'public static final String RUN_COMMAND_SERVICE_NAME = "{JAVA_NAMESPACE}.app.RunCommandService";',
    }
    for old, new in constants_replacements.items():
        constants_text = replace_once_in_text(
            constants_text, old, new, "TermuxConstants"
        )
    constants.write_text(constants_text, encoding="utf-8")

    marker = root / "HOKADIW_APP_IDENTITY.txt"
    marker.write_text(
        "\n".join(
            [
                f"APP_NAME={args.app_name}",
                f"APPLICATION_ID={args.package}",
                f"JAVA_NAMESPACE={JAVA_NAMESPACE}",
                "ABI=arm64-v8a",
                "BOOTSTRAP=bootstrap-aarch64.zip",
                "",
            ]
        ),
        encoding="utf-8",
    )

    print("Patched termux-app for HOKADIW")
    print(f"  application ID: {args.package}")
    print(f"  Java namespace: {JAVA_NAMESPACE}")
    print(f"  app name: {args.app_name}")
    print("  ABI: arm64-v8a")


if __name__ == "__main__":
    main()
