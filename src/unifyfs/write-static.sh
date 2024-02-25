#!/bin/bash
set -eu

source ./unifyfs_set_env.sh

unifyfs_env_vars=()
while IFS='=' read -r key val ; do
  if [[ $key == UNIFYFS_* ]]; then
    unifyfs_env_vars+=(-x "$key")
  fi
done < <(env)

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"

WRITE_STATIC_EXE="$(spack location -i unifyfs)/libexec/write-static"
UNIFYFS_PRELOAD_LIB="$(spack location -i unifyfs)/lib/libunifyfs_mpi_gotcha.so"

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  -x LD_PRELOAD="${UNIFYFS_PRELOAD_LIB}"
  "${unifyfs_env_vars[@]}"
  -np 4
  -map-by ppr:2:node
  # -mca orte_base_help_aggregate 0
  -mca io romio321
)

cmd_write_static=(
  "$WRITE_STATIC_EXE"
  -d -v
  # --library-api
  --mpiio
  # -b $((2**30))
  # -c $((2**20))
  # -m "$UNIFYFS_MOUNTPOINT"
)

cmd_bench=(
  "${cmd_mpirun[@]}"
  "${cmd_write_static[@]}"
)


echo "${cmd_bench[@]}"
"${cmd_bench[@]}"
