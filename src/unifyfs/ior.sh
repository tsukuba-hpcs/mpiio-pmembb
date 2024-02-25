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

UNIFYFS_PRELOAD_LIB="$(spack location -i unifyfs)/lib/libunifyfs_mpi_gotcha.so"

ppn=32
nnodes=2

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  -x LD_PRELOAD="${UNIFYFS_PRELOAD_LIB}"
  -x FI_LOG_LEVEL=debug
  -x HG_LOG_LEVEL=debug
  -x HG_LOG_SUBSYS=all
  # -x FI_PROVIDER="verbs;ofi_rxm"
  # -x FI_UNIVERSE_SIZE=4096
  "${unifyfs_env_vars[@]}"
  -np $((nnodes*ppn))
  -map-by "ppr:${ppn}:node"
  -bind-to core
  -mca io romio321
)

cmd_ior=(
  ior
  -a MPIIO
  -o /unifyfs/testfile2
  -s 1
  -b 1g
  -t 1m
  -k
  -e
)

cmd_write=(
  "${cmd_mpirun[@]}"
  "${cmd_ior[@]}"
  -w
)

cmd_read_local=(
  "${cmd_mpirun[@]}"
  "${cmd_ior[@]}"
  -r
)

cmd_read_remote=(
  "${cmd_mpirun[@]}"
  "${cmd_ior[@]}"
  -r
  -C
  -Q 1
)


echo "${cmd_write[@]}"
"${cmd_write[@]}"

echo "${cmd_read_local[@]}"
"${cmd_read_local[@]}"

echo "${cmd_read_remote[@]}"
"${cmd_read_remote[@]}"
