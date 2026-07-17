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

## Restore on a fresh install
```bash
git clone -b personal git@github.com:<me>/dots-hyprland.git ~/dots-hyprland
cd ~/dots-hyprland
./setup   # runs the end-4 installer, installing MY dots/ as the config
```
(Or run the installer from upstream first, then `./sync-personal.sh` in reverse
by copying `dots/.config/*` into `~/.config`.)

## Pull upstream updates
```bash
git fetch upstream
git checkout main && git merge upstream/main
git checkout personal && git merge main   # reconcile with my changes
```
