find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(slate)

zephyr_module()

zephyr_library_sources(
  slate_sinistra.overlay
  slate_destra.overlay
)
