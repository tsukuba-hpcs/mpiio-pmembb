#!/usr/bin/bash
set -eu


cmd_gcc=(
  gcc
  test.c
  -I/home/vscode/.cache/spack/opt/spack/linux-debian12-skylake/gcc-12.2.0/openmpi-git.v5.0.0rc12_main-gr2obkfyzml2dzx3uk5azqc5rbserf4a/include
  -L/home/vscode/.cache/spack/opt/spack/linux-debian12-skylake/gcc-12.2.0/rpmbb-0.2.0-cvsxhes26wdsifg2kb5i35bclzavjfzw/lib/rpmbb_c
  -Wl,--no-as-needed
  -lrpmbb_c
  -L/home/vscode/.cache/spack/opt/spack/linux-debian12-skylake/gcc-12.2.0/openmpi-git.v5.0.0rc12_main-gr2obkfyzml2dzx3uk5azqc5rbserf4a/lib
  -lmpi
)

echo "${cmd_gcc[@]}"
"${cmd_gcc[@]}"
