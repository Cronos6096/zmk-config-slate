{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          pythonEnv = pkgs.python3.withPackages (
            ps: with ps; [
              anytree
              canopen
              intelhex
              packaging
              progress
              protobuf
              psutil
              pyelftools
              pykwalify
              pylink-square
              pyserial
              pyyaml
              requests
              setuptools
              west
            ]
          );
        in
        {
          default = pkgs.mkShell {
            name = "zmk-slate";

            packages = with pkgs; [
              cmake
              ninja
              dtc
              gperf
              git
              gcc
              gnumake
              pkg-config
              ccache
              protobuf
              wget
              which
              diffutils

              pythonEnv

              # arm-none-eabi toolchain for the nrf52840 (nice!nano v2) targets
              gcc-arm-embedded-13
            ];

            shellHook = ''
              export PATH="${pythonEnv}/bin:$PATH"
              ZMK_PY_SITE="$(${pythonEnv}/bin/python3 -c 'import sysconfig; v = {"base": "${pythonEnv}", "platbase": "${pythonEnv}"}; print(sysconfig.get_path("purelib", vars = v))')"
              export PYTHONPATH="$ZMK_PY_SITE''${PYTHONPATH:+:$PYTHONPATH}"

              export ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
              export GNUARMEMB_TOOLCHAIN_PATH=${pkgs.gcc-arm-embedded-13}

              python3 -c "import pkg_resources, google.protobuf" >/dev/null

              echo "ZMK dev shell ready (cmake $(cmake --version | head -1 | cut -d' ' -f3), arm-none-eabi $(arm-none-eabi-gcc -dumpversion), python $(python3 --version | cut -d' ' -f2))."
            '';
          };
        }
      );
    };
}
