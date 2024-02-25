#!/bin/bash
set -eu

source ./unifyfs_set_env.sh

NNODES=$(wc --lines "${PBS_NODEFILE}" | awk '{print $1}')
UNIFYFS_SERVER_HOSTFILE="/work/NBB/$USER/unifyfs/unifyfsd.hosts"
UNIFYFS_SHAREDFS_DIR="/work/NBB/$USER/unifyfs/shared"
RANKFILE="./rankfile"

# create unifyfsd.hosts
echo "$NNODES" > "$UNIFYFS_SERVER_HOSTFILE"
cat "$PBS_NODEFILE" >> "$UNIFYFS_SERVER_HOSTFILE"

# create rankfile
rm -f $RANKFILE
touch $RANKFILE
rank=0
while IFS= read -r node; do
  echo "rank $rank=$node slot=40-47" >> $RANKFILE
  rank=$((rank+1))
done < "$PBS_NODEFILE"

unifyfs_env_vars=()
while IFS='=' read -r key val ; do
  if [[ $key == UNIFYFS_* ]]; then
    unifyfs_env_vars+=(-x "$key")
  fi
done < <(env)

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"

# config_file=$(pwd)/unifyfs.conf

cmd_unifyfsd=(
  unifyfsd
    --unifyfs-cleanup on
    --server-hostfile "$UNIFYFS_SERVER_HOSTFILE"
    --sharedfs-dir "$UNIFYFS_SHAREDFS_DIR"
)

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  # -x FI_PROVIDER="verbs;ofi_rxm"
  # -x FI_UNIVERSE_SIZE=4096
  "${unifyfs_env_vars[@]}"
  -np 2
  -rf "$RANKFILE"
  # -map-by ppr:1:node:PE=8
)

cmd_start_unifyfs=(
  "${cmd_mpirun[@]}"
  "${cmd_unifyfsd[@]}"
)

rm -f "${UNIFYFS_LOG_DIR:?}/unifyfsd.log"*

echo "${cmd_start_unifyfs[@]}"
"${cmd_start_unifyfs[@]}"
