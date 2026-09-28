# Slate

Build via GitHub Actions (runs the 5 entries in `build.yaml`, uploads artifacts)
or locally with Nix:

```sh
export SLATE=/path/to/zmk-config-slate
export WS=/path/to/zmk-workspace        # west init'd from zmkfirmware/zmk v0.2
nix develop "$SLATE#default" -c west ...   # or .#dfu for nrfutil
```

## Build (run from $WS)

```sh
# half, left
nix develop "$SLATE#default" -c west build -b nice_nano_v2 -d build/slate-left -s zmk/app -- \
  -DSHIELD=slate_sinistra -DZMK_CONFIG="$SLATE/config" -DZMK_EXTRA_MODULES="$SLATE"
# half, right: same, -DSHIELD=slate_destra -d build/slate-right

# dongle central (HEX, no UF2, DFU-packageable)
nix develop "$SLATE#default" -c west build -b nrf52840dongle_nrf52840 -d build/slate-dongle -s zmk/app -- \
  -DSHIELD=slate_dongle -DSNIPPET=studio-rpc-usb-uart \
  -DZMK_CONFIG="$SLATE/config" -DZMK_EXTRA_MODULES="$SLATE" \
  -DCONFIG_ZMK_STUDIO=y -DCONFIG_BT_MAX_CONN=5 -DCONFIG_BT_MAX_PAIRED=5 -DCONFIG_ZMK_SLEEP=n \
  -DCONFIG_BUILD_OUTPUT_HEX=y -DCONFIG_BUILD_OUTPUT_UF2=n -DCONFIG_FLASH_LOAD_SIZE=0xDB000

# bond-wipe images: shield settings_reset on nice_nano_v2 (uf2) and nrf52840dongle_nrf52840 (hex)
```

## Flash

| Device | Image                                       | Method                                                                                                                                                                |
| ------ | ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| halves | `result/slate-left.uf2` / `slate-right.uf2` | double-tap reset → drag onto `NICENANO`                                                                                                                               |
| dongle | `result/slate-dongle-dfu.zip`               | hold button + power-cycle → in DFU mode it is a single ttyACM → `nix develop .#dfu -c tools/dongle-dfu.sh -b "$WS/build/slate-dongle/zephyr" -f` → power-cycle to run |

## Pairing / troubleshooting

- First run or after a reset: power the halves and the dongle on **at the same
  time** and they bond automatically.
- Won't pair (`Security failed … err 4`, split link never encrypts): a half
  holds a stale bond. Reset **both sides** and re-power together — flash
  `slate-settings-reset.uf2` (or `slate-dongle-settings-reset.zip`), wait ~10 s,
  reflash the normal image (reflashing does not wipe bonds), power all up
  together.
- USB console for debugging: add `-DSNIPPET=zmk-usb-logging`. Never combine with
  `CONFIG_ZMK_LOG_MODE_IMMEDIATE` on the dongle (boot hang).

## Artifacts

| File                                                          | Image                   |
| ------------------------------------------------------------- | ----------------------- |
| `slate-left.uf2`, `slate-right.uf2`                           | halves                  |
| `slate-dongle-dfu.zip`, `slate-dongle.hex`                    | central (DFU pkg + HEX) |
| `slate-settings-reset.uf2`, `slate-dongle-settings-reset.zip` | bond wipe               |

