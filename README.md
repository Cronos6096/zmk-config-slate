# Slate

The dongle has no UF2 bootloader, so it is built to HEX and packaged for Nordic
Open DFU; the halves produce UF2 images for drag-and-drop flashing.

## Repository layout

| Path                          | What it is                                                               |
| ----------------------------- | ------------------------------------------------------------------------ |
| `config/`                     | keymaps, shield definitions (passed via `-DZMK_CONFIG`)                  |
| `boards/`                     | Slate hardware definitions (this repo is a West module, `board_root: .`) |
| `build.yaml`                  | the 5 build entries shared by CI and local builds                        |
| `zephyr/module.yml`           | module marker (`ZMK_EXTRA_MODULES`)                                      |
| `patches/`                    | out-of-tree ZMK source patches, applied before building                  |
| `.github/workflows/build.yml` | self-contained CI builder (applies the patches)                          |
| `tools/dongle-dfu.sh`         | package + flash the dongle (Nordic Open DFU)                             |
| `flake.nix`                   | Nix dev shells: `#default` for `west`, `#dfu` adds `nrfutil`             |
| `result/`                     | locally built artifacts (gitignored; CI produces the same five)          |

## Prerequisites

```sh
export SLATE=/path/to/zmk-config-slate
export WS=/path/to/zmk-workspace        # west init'd from zmkfirmware/zmk v0.2
```

Run every build from `$WS`. Tooling comes from the flake:

```sh
nix develop "$SLATE#default" -c west ...                 # build
nix develop "$SLATE#dfu"    -c tools/dongle-dfu.sh ...   # flash dongle (has nrfutil)
```

> Local builds need the out-of-tree patch applied to the ZMK tree first (CI does
> this automatically):
>
> ```sh
> git -C "$WS/zmk" apply "$SLATE/patches"/*.patch   # re-apply after `west update`
> ```

## Build (run from `$WS`)

Prefer a fresh `-d build/…` directory or `-p` for a pristine build: reusing a
directory with a changed configuration fails.

```sh
# halves
nix develop "$SLATE#default" -c west build -p -b nice_nano_v2 -d build/slate-left -s zmk/app -- \
  -DSHIELD=slate_sinistra -DZMK_CONFIG="$SLATE/config" -DZMK_EXTRA_MODULES="$SLATE"
# right half: same, -DSHIELD=slate_destra -d build/slate-right

# dongle central (HEX, no UF2, DFU-packageable)
nix develop "$SLATE#default" -c west build -p -b nrf52840dongle_nrf52840 -d build/slate-dongle -s zmk/app -- \
  -DSHIELD=slate_dongle -DSNIPPET=studio-rpc-usb-uart \
  -DZMK_CONFIG="$SLATE/config" -DZMK_EXTRA_MODULES="$SLATE" \
  -DCONFIG_ZMK_STUDIO=y -DCONFIG_BT_MAX_CONN=5 -DCONFIG_BT_MAX_PAIRED=5 -DCONFIG_ZMK_SLEEP=n \
  -DCONFIG_BUILD_OUTPUT_HEX=y -DCONFIG_BUILD_OUTPUT_UF2=n -DCONFIG_FLASH_LOAD_SIZE=0xDB000

# bond-wipe images (settings_reset shield on nice_nano_v2)
nix develop "$SLATE#default" -c west build -p -b nice_nano_v2 -d build/slate-settings-reset -s zmk/app -- \
  -DSHIELD=settings_reset -DZMK_CONFIG="$SLATE/config" -DZMK_EXTRA_MODULES="$SLATE"

# dongle bond-wipe image (settings_reset on the dongle board, HEX output)
nix develop "$SLATE#default" -c west build -p -b nrf52840dongle_nrf52840 -d build/slate-dongle-settings-reset -s zmk/app -- \
  -DSHIELD=settings_reset -DZMK_CONFIG="$SLATE/config" -DZMK_EXTRA_MODULES="$SLATE" \
  -DCONFIG_BUILD_OUTPUT_HEX=y -DCONFIG_BUILD_OUTPUT_UF2=n -DCONFIG_FLASH_LOAD_SIZE=0xDB000
```

## CI pipeline

`.github/workflows/build.yml` is a self-contained builder that mirrors ZMK's
official `build-user-config.yml` action, with one addition: it applies
`patches/*.patch` to the ZMK tree before compiling (the stock action has no way
to carry source patches).

## Flash

| Device             | Image                                             | Method                                                                                                                                                     |
| ------------------ | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| halves (normal)    | `result/slate-left.uf2`, `result/slate-right.uf2` | double-tap reset → drag onto `NICENANO`                                                                                                                    |
| halves (bond wipe) | `result/slate-settings-reset.uf2`                 | same drag-and-drop (clears BLE bonds on next boot)                                                                                                         |
| dongle (normal)    | `result/slate-dongle-dfu.zip`                     | hold button + power-cycle → single `ttyACM` → `nix develop "$SLATE#dfu" -c tools/dongle-dfu.sh -b "$WS/build/slate-dongle/zephyr" -f` → power-cycle to run |
| dongle (bond wipe) | `result/slate-dongle-settings-reset.zip`          | same DFU flow (clears bonds on next boot)                                                                                                                  |

## Pairing / troubleshooting

- First run or after a reset: power the halves and the dongle on **at the same
  time** and they bond automatically.
- Split link wedged after a hot-unplug / reboot (`Security failed … err 4`, link
  never encrypts): one side holds a bond the other lost — the dongle can drop
  its stored keys while the half keeps its own. With the patched halves this
  **self-heals**: `peripheral.c` un-pairs on any split security failure, the
  half re-advertises, and the dongle re-pairs automatically within seconds — no
  reset needed. Unplugging still disconnects the link (the dongle has no
  battery); replugging brings it back on its own. Requires
  `result/slate-left.uf2` / `result/slate-right.uf2` (see `patches/0001-…`).
- If a half still holds a bad bond (e.g. after flashing an unpatched image),
  reset **both sides**: flash `slate-settings-reset.uf2` (or
  `slate-dongle-settings-reset.zip`), wait ~10 s, reflash the normal image
  (reflashing does not wipe bonds), power all up together.
- USB console for debugging: add `-DSNIPPET=zmk-usb-logging`. Never combine with
  `CONFIG_ZMK_LOG_MODE_IMMEDIATE` on the dongle (boot hang).

## Artifacts

| File                                       | Image                       |
| ------------------------------------------ | --------------------------- |
| `slate-left.uf2`, `slate-right.uf2`        | halves                      |
| `slate-dongle-dfu.zip`, `slate-dongle.hex` | central (DFU package + HEX) |
| `slate-settings-reset.uf2`                 | half bond wipe              |
| `slate-dongle-settings-reset.zip`          | dongle bond wipe            |

