#!/usr/bin/bash
set -eu

env_list=(
  mpiio-pmembb
  mpiio-pmembb-profile
  mpiio-pmembb-no-optim
  mpiio-pmembb-deferred-open
  mpiio-pmembb-agg-read
)

spack uninstall --force --all --dependents openmpi

for spack_env in "${env_list[@]}"; do
  echo $spack_env
  spack env activate "$spack_env"
  spack concretize -fU
  spack install
  if [ "$spack_env" = "mpiio-pmembb" ]; then
    spack module tcl refresh --delete-tree -y
  else
    spack module tcl refresh -y
  fi
  spack env deactivate
done
