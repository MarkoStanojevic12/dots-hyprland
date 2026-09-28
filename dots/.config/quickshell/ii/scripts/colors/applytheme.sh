#!/usr/bin/env bash
# Applies a hand-written color theme (a JSON palette in ~/.config/illogical-impulse/themes)
# to the shell, Hyprland, hyprlock, fuzzel, GTK, Qt and the terminal.
#
# Usage:
#   applytheme.sh <name>|--apply <name>   apply a theme and make it stick
#   applytheme.sh --reapply [--mode M]    re-render the active theme
#   applytheme.sh --clear                 go back to wallpaper-generated colors
#   applytheme.sh --export <name>         save the current palette as a new theme
#   applytheme.sh --list                  refresh the theme index used by the settings UI

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
THEMES_DIR="$XDG_CONFIG_HOME/illogical-impulse/themes"
MATUGEN_CONFIG="$XDG_CONFIG_HOME/matugen/config.toml"
GENERATED_DIR="$STATE_DIR/user/generated"
THEME_INDEX="$GENERATED_DIR/themes.json"
TOOLS="$SCRIPT_DIR/theme_tools.py"
TERMSCHEME="$SCRIPT_DIR/terminal/scheme-base.json"

die() {
    echo "[applytheme] $1" >&2
    exit 1
}

config_get() {
    jq -r "$1" "$SHELL_CONFIG_FILE" 2>/dev/null
}

set_custom_theme() {
    local name="$1"
    [ -f "$SHELL_CONFIG_FILE" ] || return
    jq --arg name "$name" '.appearance.palette.customTheme = $name' "$SHELL_CONFIG_FILE" \
        > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
}

refresh_index() {
    python3 "$TOOLS" index --dir "$THEMES_DIR" --out "$THEME_INDEX"
}

theme_value() {
    # theme_value <file> <mode> <key>
    python3 -c '
import json, sys
theme = json.load(open(sys.argv[1]))
palette = dict(theme.get("colors", {}))
palette.update(theme.get(sys.argv[2], {}) or {})
print(palette.get(sys.argv[3], ""))
' "$1" "$2" "$3"
}

theme_mode() {
    python3 -c '
import json, sys
print(json.load(open(sys.argv[1])).get("mode", ""))
' "$1"
}

current_mode() {
    if [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")" == "prefer-dark" ]]; then
        echo dark
    else
        echo light
    fi
}

apply_gtk_mode() {
    local mode="$1"
    if [[ "$mode" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    else
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
    fi
}

generate_terminal_colors() {
    local theme_file="$1" mode="$2" primary="$3"
    local venv
    venv="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")"
    if [ ! -f "$venv/bin/activate" ]; then
        echo "[applytheme] no python venv, keeping previous terminal colors" >&2
        return
    fi

    local args=(--color "$primary" --mode "$mode" --termscheme "$TERMSCHEME" --blend_bg_fg
        --cache "$GENERATED_DIR/color.txt")
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        local harmony harmonize_threshold term_fg_boost
        harmony=$(config_get '.appearance.wallpaperTheming.terminalGenerationProps.harmony')
        harmonize_threshold=$(config_get '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold')
        term_fg_boost=$(config_get '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost')
        [[ "$harmony" != "null" && -n "$harmony" ]] && args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && args+=(--term_fg_boost "$term_fg_boost")
    fi

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    python3 "$SCRIPT_DIR/generate_colors_material.py" "${args[@]}" > "$GENERATED_DIR/material_colors.scss"
    deactivate

    python3 "$TOOLS" patch-scss --theme "$theme_file" --scss "$GENERATED_DIR/material_colors.scss" --mode "$mode"
}

apply_theme() {
    local name="$1" mode_flag="$2"
    local theme_file="$THEMES_DIR/$name.json"
    [ -f "$theme_file" ] || die "no such theme: $theme_file"
    command -v matugen >/dev/null || die "matugen not found"

    local mode="$mode_flag"
    [[ -z "$mode" ]] && mode="$(theme_mode "$theme_file")"
    [[ "$mode" != "dark" && "$mode" != "light" ]] && mode="$(current_mode)"

    local primary
    primary="$(theme_value "$theme_file" "$mode" primary)"
    [[ "$primary" =~ ^#[0-9a-fA-F]{6}$ ]] || primary="#7f67be"

    mkdir -p "$GENERATED_DIR"
    apply_gtk_mode "$mode"

    if [[ "$(config_get '.appearance.wallpaperTheming.enableAppsAndShell')" == "false" ]]; then
        echo "[applytheme] app and shell theming disabled, nothing to do"
        return
    fi

    local tmpdir
    tmpdir="$(mktemp -d)" || die "cannot create temp dir"
    trap 'rm -rf "$tmpdir"' RETURN

    # matugen needs a complete render document; seed one from the theme's primary,
    # then overwrite every role the theme defines.
    matugen -q -c "$MATUGEN_CONFIG" --dry-run --mode "$mode" --json hex color hex "$primary" \
        > "$tmpdir/seed.json" || die "matugen could not build a seed palette"

    local wallpaper
    wallpaper="$(config_get '.background.wallpaperPath')"
    [[ "$wallpaper" == "null" ]] && wallpaper=""

    python3 "$TOOLS" build --theme "$theme_file" --seed "$tmpdir/seed.json" \
        --mode "$mode" --image "$wallpaper" --out "$tmpdir/render.json" || die "could not build theme palette"

    matugen -q -c "$MATUGEN_CONFIG" --mode "$mode" json "$tmpdir/render.json" || die "matugen render failed"

    if [[ "$(config_get '.appearance.wallpaperTheming.enableTerminal')" != "false" ]]; then
        generate_terminal_colors "$theme_file" "$mode" "$primary"
    fi

    "$SCRIPT_DIR/applycolor.sh"

    if [[ "$(config_get '.appearance.wallpaperTheming.enableQtApps')" != "false" ]]; then
        "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant scheme-tonal-spot &
    fi
    "$SCRIPT_DIR/code/material-code-set-color.sh" &

    refresh_index > /dev/null
}

main() {
    local action="" name="" mode_flag=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply)
                action="apply"; name="$2"; shift 2 ;;
            --reapply)
                action="reapply"; shift ;;
            --clear)
                action="clear"; shift ;;
            --export)
                action="export"; name="$2"; shift 2 ;;
            --list)
                action="list"; shift ;;
            --mode)
                mode_flag="$2"; shift 2 ;;
            -h|--help)
                sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
            *)
                [[ -z "$name" ]] && name="$1" && action="${action:-apply}"
                shift ;;
        esac
    done

    mkdir -p "$THEMES_DIR" "$GENERATED_DIR"

    case "$action" in
        list)
            refresh_index
            ;;
        export)
            [[ -n "$name" ]] || die "--export needs a name"
            local stem
            stem="$(echo "$name" | tr '[:upper:] ' '[:lower:]-')"
            python3 "$TOOLS" export \
                --colors "$GENERATED_DIR/colors.json" \
                --scss "$GENERATED_DIR/material_colors.scss" \
                --name "$name" \
                --out "$THEMES_DIR/$stem.json" || exit 1
            refresh_index > /dev/null
            ;;
        clear)
            set_custom_theme ""
            "$SCRIPT_DIR/switchwall.sh" --noswitch
            ;;
        reapply)
            name="$(config_get '.appearance.palette.customTheme')"
            [[ -n "$name" && "$name" != "null" ]] || die "no custom theme is active"
            apply_theme "$name" "$mode_flag"
            ;;
        apply)
            [[ -n "$name" ]] || die "no theme name given"
            name="${name%.json}"
            [ -f "$THEMES_DIR/$name.json" ] || die "no such theme: $THEMES_DIR/$name.json"
            set_custom_theme "$name"
            apply_theme "$name" "$mode_flag"
            ;;
        *)
            die "nothing to do; try --help"
            ;;
    esac
}

main "$@"
