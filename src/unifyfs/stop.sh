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

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  "${unifyfs_env_vars[@]}"
  -np 2
  -map-by ppr:1:node
)

cmd_pkill=(
  pkill -n unifyfsd
)

cmd_stop_unifyfs=(
  "${cmd_mpirun[@]}"
  "${cmd_pkill[@]}"
)

echo "${cmd_stop_unifyfs[@]}"
"${cmd_stop_unifyfs[@]}"
