#!/usr/bin/env python3
"""Helpers for hand-written color themes (see applytheme.sh)."""

import argparse
import json
import os
import re
import sys

M3_KEYS = [
    "background", "error", "error_container", "inverse_on_surface", "inverse_primary",
    "inverse_surface", "on_background", "on_error", "on_error_container", "on_primary",
    "on_primary_container", "on_primary_fixed", "on_primary_fixed_variant", "on_secondary",
    "on_secondary_container", "on_secondary_fixed", "on_secondary_fixed_variant", "on_surface",
    "on_surface_variant", "on_tertiary", "on_tertiary_container", "on_tertiary_fixed",
    "on_tertiary_fixed_variant", "outline", "outline_variant", "primary", "primary_container",
    "primary_fixed", "primary_fixed_dim", "scrim", "secondary", "secondary_container",
    "secondary_fixed", "secondary_fixed_dim", "shadow", "surface", "surface_bright",
    "surface_container", "surface_container_high", "surface_container_highest",
    "surface_container_low", "surface_container_lowest", "surface_dim", "surface_tint",
    "surface_variant", "tertiary", "tertiary_container", "tertiary_fixed", "tertiary_fixed_dim",
]

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def camelize(key):
    head, *rest = key.split("_")
    return head + "".join(word.capitalize() for word in rest)


def fail(message):
    print(f"[theme_tools] {message}", file=sys.stderr)
    sys.exit(1)


def load_theme(path):
    try:
        with open(path) as handle:
            theme = json.load(handle)
    except (OSError, json.JSONDecodeError) as err:
        fail(f"cannot read theme {path}: {err}")
    if not isinstance(theme, dict):
        fail(f"theme {path} must be a JSON object")
    return theme


def palettes_of(theme, path):
    base = theme.get("colors", {})
    if not isinstance(base, dict):
        fail(f"{path}: 'colors' must be an object")
    palettes = {}
    for mode in ("dark", "light"):
        merged = dict(base)
        override = theme.get(mode, {})
        if override and not isinstance(override, dict):
            fail(f"{path}: '{mode}' must be an object")
        merged.update(override or {})
        for key, value in merged.items():
            if not isinstance(value, str) or not HEX_RE.match(value):
                fail(f"{path}: {mode}.{key} is '{value}', expected #rrggbb")
        palettes[mode] = merged
    if not palettes["dark"] and not palettes["light"]:
        fail(f"{path}: no colors defined")
    return palettes


def warn_missing(palette, mode):
    missing = [key for key in M3_KEYS if key not in palette]
    if missing:
        print(
            f"[theme_tools] {mode}: {len(missing)} role(s) not in theme, "
            f"keeping generated values: {', '.join(missing)}",
            file=sys.stderr,
        )


def cmd_build(args):
    theme = load_theme(args.theme)
    palettes = palettes_of(theme, args.theme)
    warn_missing(palettes[args.mode], args.mode)

    try:
        with open(args.seed) as handle:
            seed = json.load(handle)
    except (OSError, json.JSONDecodeError) as err:
        fail(f"cannot read seed palette {args.seed}: {err}")

    colors = seed.setdefault("colors", {})
    for mode in ("dark", "light"):
        for key, value in palettes[mode].items():
            colors.setdefault(key, {})[mode] = {"color": value}
        primary = palettes[mode].get("primary")
        if primary:
            colors.setdefault("source_color", {})[mode] = {"color": primary}
    for key, value in palettes[args.mode].items():
        colors.setdefault(key, {})["default"] = {"color": value}
    primary = palettes[args.mode].get("primary")
    if primary:
        colors.setdefault("source_color", {})["default"] = {"color": primary}

    seed["mode"] = args.mode
    seed["is_dark_mode"] = args.mode == "dark"
    if args.image:
        seed["image"] = args.image

    with open(args.out, "w") as handle:
        json.dump(seed, handle)


def cmd_patch_scss(args):
    """Replace the generated M3 (and optional terminal) values with the theme's own."""
    theme = load_theme(args.theme)
    palette = palettes_of(theme, args.theme)[args.mode]

    replacements = {camelize(key): value for key, value in palette.items()}
    terminal = theme.get("terminal", {}) or {}
    for key, value in terminal.items():
        if not HEX_RE.match(str(value)):
            fail(f"{args.theme}: terminal.{key} is '{value}', expected #rrggbb")
        replacements[key] = value
    replacements["darkmode"] = "True" if args.mode == "dark" else "False"

    try:
        with open(args.scss) as handle:
            lines = handle.read().splitlines()
    except OSError as err:
        fail(f"cannot read {args.scss}: {err}")

    out = []
    for line in lines:
        name = line.split(":", 1)[0].lstrip("$").strip() if ":" in line else None
        if name in replacements:
            out.append(f"${name}: {replacements[name]};")
        else:
            out.append(line)

    with open(args.scss, "w") as handle:
        handle.write("\n".join(out) + "\n")


def cmd_index(args):
    entries = []
    if os.path.isdir(args.dir):
        for filename in sorted(os.listdir(args.dir)):
            if not filename.endswith(".json"):
                continue
            path = os.path.join(args.dir, filename)
            try:
                with open(path) as handle:
                    theme = json.load(handle)
            except (OSError, json.JSONDecodeError) as err:
                print(f"[theme_tools] skipping {filename}: {err}", file=sys.stderr)
                continue
            stem = filename[: -len(".json")]
            mode = theme.get("mode", "dark")
            palette = dict(theme.get("colors", {}))
            palette.update(theme.get(mode, {}) or {})
            entries.append({
                "file": stem,
                "name": theme.get("name", stem),
                "mode": mode,
                "primary": palette.get("primary", "#000000"),
                "background": palette.get("background", "#000000"),
            })
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as handle:
        json.dump(entries, handle, indent=2)
    for entry in entries:
        print(f"{entry['file']}\t{entry['name']}")


def cmd_export(args):
    try:
        with open(args.colors) as handle:
            colors = json.load(handle)
    except (OSError, json.JSONDecodeError) as err:
        fail(f"cannot read current palette {args.colors}: {err}")

    terminal = {}
    mode = "dark"
    if os.path.exists(args.scss):
        with open(args.scss) as handle:
            for line in handle:
                if ":" not in line:
                    continue
                name, value = line.split(":", 1)
                name = name.strip().lstrip("$")
                value = value.strip().rstrip(";").strip()
                if name == "darkmode":
                    mode = "dark" if value.lower().startswith("t") else "light"
                elif re.fullmatch(r"term\d+", name) and HEX_RE.match(value):
                    terminal[name] = value

    theme = {
        "name": args.name,
        "mode": mode,
        "colors": {key: colors[key] for key in M3_KEYS if key in colors},
    }
    if terminal:
        theme["terminal"] = terminal

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as handle:
        json.dump(theme, handle, indent=2)
    print(args.out)


def main():
    parser = argparse.ArgumentParser(description="Custom theme helpers")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build", help="merge a theme into a matugen render document")
    build.add_argument("--theme", required=True)
    build.add_argument("--seed", required=True)
    build.add_argument("--mode", choices=["dark", "light"], default="dark")
    build.add_argument("--image", default="")
    build.add_argument("--out", required=True)
    build.set_defaults(func=cmd_build)

    patch = subparsers.add_parser("patch-scss", help="write theme colors into material_colors.scss")
    patch.add_argument("--theme", required=True)
    patch.add_argument("--scss", required=True)
    patch.add_argument("--mode", choices=["dark", "light"], default="dark")
    patch.set_defaults(func=cmd_patch_scss)

    index = subparsers.add_parser("index", help="list available themes as JSON")
    index.add_argument("--dir", required=True)
    index.add_argument("--out", required=True)
    index.set_defaults(func=cmd_index)

    export = subparsers.add_parser("export", help="save the live palette as a theme file")
    export.add_argument("--colors", required=True)
    export.add_argument("--scss", required=True)
    export.add_argument("--name", required=True)
    export.add_argument("--out", required=True)
    export.set_defaults(func=cmd_export)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
