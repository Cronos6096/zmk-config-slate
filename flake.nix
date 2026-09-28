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

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      legacyPkgs = system: nixpkgs.legacyPackages.${system};

      # pc-nrfutil 5.2.0 (`nrfutil` on PyPI) is Python 2 code, but it is the only
      # tool that builds the Nordic Open DFU packages the nRF52840 dongle's stock
      # bootloader accepts (nixpkgs' `nrfutil` is only Nordic's toolchain manager
      # and ships unpatched, non-runnable generic-linux binaries). It is patched
      # here for Python 3, and the Bluetooth/zigbee imports that `pkg generate` and
      # `dfu usb-serial` never use are dropped so the BLE native stack is not needed.
      nrfutil =
        pkgs:
        let
          nrfutilPkg = pkgs.python3Packages.buildPythonPackage {
            pname = "nrfutil";
            version = "5.2.0";
            format = "setuptools";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/95/bd/c69458ec1b9f66b5874bcf7df60f4e768b5fa137663637241628bfdea135/nrfutil-5.2.0.tar.gz";
              hash = "sha256-RgunGpYLveayH9uPxPlBPGhArskSR3eRRAHuwr/zbS0=";
            };
            # The sdist ships CRLF sources; the patches are written against LF, and
            # prePatch runs before they are applied.
            prePatch = ''
              find . -name '*.py' -exec sed -i 's/\r$//' {} +
            '';
            patches = [
              ./nix/patches/nrfutil-5.2.0-py3.patch
              ./nix/patches/nrfutil-5.2.0-sdist.patch
            ];
            dependencies = [ ];
            dontCheck = true;
            dontFixup = true;
            pythonRuntimeDepsCheckHook = false;
            meta.description = "Nordic DFU packaging/flash tool (Python 3 port)";
            meta.license = pkgs.lib.licenses.asl20;
            platforms = pkgs.lib.platforms.unix;
          };

          # Only the exception classes are used by the DFU commands; the driver
          # itself needs Nordic's native BLE library, which we do not ship.
          pcBleDriverPy = pkgs.python3Packages.buildPythonPackage {
            pname = "pc_ble_driver_py";
            version = "0.11.4";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/38/6f/0bd202ea117a2c944234992f4d9f8c8b68964470dacc34164f20111712a9/pc_ble_driver_py-0.11.4.tar.gz";
              hash = "sha256-hETEEWIdOKYkZChptcYOEANiztEBbInE8Fn3l4trtGs=";
            };
            dependencies = [ ];
            dontCheck = true;
            dontFixup = true;
            pythonRuntimeDepsCheckHook = false;
            meta.license = pkgs.lib.licenses.asl20;
            platforms = pkgs.lib.platforms.unix;
          };

          env = pkgs.python3.withPackages (ps: [
            nrfutilPkg
            pcBleDriverPy
            ps.click
            ps.crcmod
            ps.intelhex
            ps.protobuf
            ps.pyserial
            ps.pyyaml
            ps.six
            ps.tqdm
          ]);
        in
        # writeShellScriptBin (not writeShellScript): a bare writeShellScript
        # output is a single file, so a devShell's `$drv/bin` PATH entry would
        # not exist and the shell would not see the command at all.
        pkgs.writeShellScriptBin "nrfutil" ''
          # nrfutil ships 2019-era protobuf stubs, which only protobuf's pure
          # python parser accepts; also keep the ZMK shell's PYTHONPATH out.
          export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

          # `nrfutil` with no arguments makes click exit non-zero, and nixpkgs
          # smoke-executes every entry of a devShell's `packages`, so turn that
          # into a plain help request to keep `nix develop .#dfu` buildable.
          if [ $# -eq 0 ]; then
            set -- --help
          fi

          exec env -u PYTHONPATH ${env}/bin/nrfutil "$@"
        '';

      mkZmkShell =
        pkgs:
        {
          extraPackages ? [ ],
          extraShellHook ? "",
        }:
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
        pkgs.mkShell {
          name = "zmk-slate";

          packages =
            with pkgs;
            [
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

              # arm-none-eabi toolchain for the nrf52840 (nice!nano v2 halves and
              # the nrf52840dongle_nrf52840 central)
              gcc-arm-embedded-13
            ]
            ++ extraPackages;

          shellHook = ''
            export PATH="${pythonEnv}/bin:$PATH"
            ZMK_PY_SITE="$(${pythonEnv}/bin/python3 -c 'import sysconfig; v = {"base": "${pythonEnv}", "platbase": "${pythonEnv}"}; print(sysconfig.get_path("purelib", vars = v))')"
            export PYTHONPATH="$ZMK_PY_SITE''${PYTHONPATH:+:$PYTHONPATH}"

            export ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
            export GNUARMEMB_TOOLCHAIN_PATH=${pkgs.gcc-arm-embedded-13}

            python3 -c "import pkg_resources, google.protobuf" >/dev/null

            echo "ZMK dev shell ready (cmake $(cmake --version | head -1 | cut -d' ' -f3), arm-none-eabi $(arm-none-eabi-gcc -dumpversion), python $(python3 --version | cut -d' ' -f2))."
          ''
          + extraShellHook;
        };
    in
    {
      devShells = (
        forAllSystems (system: {
          default = mkZmkShell (legacyPkgs system) { };

          # nix develop .#dfu — the same environment plus nrfutil, for turning a
          # built zmk.hex into a Nordic Open DFU package and flashing the dongle.
          dfu = mkZmkShell (legacyPkgs system) {
            extraPackages = [ (nrfutil (legacyPkgs system)) ];
            extraShellHook = ''
              if command -v nrfutil > /dev/null; then
                echo "nrfutil available: tools/dongle-dfu.sh packages and flashes the nRF52840 dongle."
              fi
            '';
          };
        })
      );
    };
}
