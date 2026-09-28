#!/usr/bin/env bash
# Package the built central firmware into a Nordic Open DFU package and,
# optionally, flash it to the AliExpress nRF52840 dongle.
#
# The dongle's stock bootloader speaks Nordic Open DFU over USB CDC, so it needs
# a DFU package rather than the UF2 file the nice!nano halves use. Run this
# inside `nix develop .#dfu`, which provides nrfutil.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZMK_WORKSPACE:-$(dirname -- "$repo_root")/zmk-workspace}"
build_dir="$workspace/build/slate-dongle-df/zephyr"
output=""
port=""
flash=0

usage() {
    cat <<EOF
Usage: tools/dongle-dfu.sh [options]

  -b, --build-dir DIR   directory containing zmk.hex (default: $build_dir)
  -o, --output FILE     DFU package to write (default: <build-dir>/slate-dongle-dfu.zip)
  -p, --port PORT       serial port to flash over (default: autodetect if unambiguous)
  -f, --flash           flash the package after building it
  -h, --help            show this help

Enter DFU mode by holding the dongle's button while power-cycling it; the
application runs again after the next power cycle.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -b | --build-dir)
            build_dir="$2"
            shift 2
            ;;
        -o | --output)
            output="$2"
            shift 2
            ;;
        -p | --port)
            port="$2"
            shift 2
            ;;
        -f | --flash)
            flash=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! command -v nrfutil >/dev/null; then
    echo "nrfutil not found; run this via: nix develop .#dfu -c tools/dongle-dfu.sh" >&2
    exit 1
fi

hex="$build_dir/zmk.hex"
if [ ! -f "$hex" ]; then
    echo "no firmware at $hex; build it first:" >&2
    echo "  nix develop -c west build -b nrf52840dongle_nrf52840 -d $build_dir -s zmk/app -- \\" >&2
    echo "    -DSHIELD=slate_dongle -DSNIPPET=studio-rpc-usb-uart \\" >&2
    echo "    -DCONFIG_BUILD_OUTPUT_HEX=y -DCONFIG_BUILD_OUTPUT_UF2=n \\" >&2
    echo "    -DCONFIG_FLASH_LOAD_SIZE=0xDB000 -DCONFIG_ZMK_SLEEP=n" >&2
    exit 1
fi

output="${output:-$build_dir/slate-dongle-dfu.zip}"

# No --bootloader-version: it is only valid together with a --bootloader image,
# and the bootloader here is the stock one already on the dongle.
nrfutil pkg generate \
    --hw-version 52 \
    --sd-req 0 \
    --application "$hex" \
    --application-version 1 \
    --application-version-string "0.1.0" \
    "$output"

if [ "$flash" -eq 0 ]; then
    echo "Packaged $hex -> $output"
    exit 0
fi

if [ -z "$port" ]; then
    # In DFU mode the dongle exposes a single CDC; in application mode it shows
    # up as two. Only guess when there is no ambiguity.
    candidates=()
    for device in /dev/ttyACM*; do
        [ -e "$device" ] && candidates+=("$device")
    done
    if [ "${#candidates[@]}" -ne 1 ]; then
        echo "cannot pick a port automatically, pass -p:" >&2
        printf '  %s\n' "${candidates[@]:-no /dev/ttyACM* found}" >&2
        exit 1
    fi
    port="${candidates[0]}"
fi

echo "Flashing $output over $port ..."
nrfutil dfu usb-serial -pkg "$output" -p "$port"
echo "Flashed. Power-cycle the dongle to start the application."
