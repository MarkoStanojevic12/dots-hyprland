# Personal fork notes

This is my fork of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland).
My customizations live on the **`personal`** branch; **`main`** tracks upstream
unchanged so I can pull updates.

## Layout
- Live configs are edited in `~/.config` as usual.
- `./sync-personal.sh` mirrors the areas I customize (`quickshell/ii`, `hypr`)
  into `dots/.config/`, excluding matugen/fish-generated files that churn.

## Save changes after editing my config
```bash
cd ~/dots-hyprland
./sync-personal.sh
git add -A
git commit -m "..."
git push origin personal
```

## Extra dependencies
Packages my customizations need that upstream's installer does not pull in.
They go here rather than into `sdata/dist-arch/illogical-impulse-*/PKGBUILD`,
which is upstream's and would conflict on every merge.
```bash
sudo pacman -S qmltermwidget
```
- `qmltermwidget` — the pty behind the play button on a code block in the
  Claude sidebar (`modules/ii/sidebarLeft/aiChat/InlineTerminal.qml`). Without
  it that button disappears; nothing else in the chat is affected.

## Restore on a fresh install
```bash
git clone -b personal git@github.com:<me>/dots-hyprland.git ~/dots-hyprland
cd ~/dots-hyprland
./setup   # runs the end-4 installer, installing MY dots/ as the config
```
(Or run the installer from upstream first, then `./sync-personal.sh` in reverse
by copying `dots/.config/*` into `~/.config`. Then install the extra
dependencies above.)

## Pull upstream updates
One command — fetches end-4, merges into `personal`, applies to live, reloads:
```bash
./update-from-upstream.sh
```
If it reports merge conflicts, resolve them, `git add -A && git commit --no-edit`,
then re-run it to finish applying to live. It never overwrites matugen-generated
color files, so theming stays intact.
