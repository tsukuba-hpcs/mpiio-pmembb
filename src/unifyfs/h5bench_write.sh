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

ppn=4
nnodes=2

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  -x LD_PRELOAD="${UNIFYFS_PRELOAD_LIB}"
  "${unifyfs_env_vars[@]}"
  -np $((nnodes*ppn))
  -map-by "ppr:${ppn}:node"
  -bind-to core
  -mca io romio321
)

h5bench_cfg="$(pwd)/h5bench.cfg"

cmd_h5bench_write=(
  "${cmd_mpirun[@]}"
  h5bench_write
  "${h5bench_cfg}"
  "${UNIFYFS_MOUNTPOINT}/rw.h5"
)

"${cmd_h5bench_write[@]}"


# cmd_sample=(
# mpirun
# --leave-session-attached
# -hostfile
# /var/opt/nec/nqsv/jsv/jobfile/0.174276.10/mpinodes
# -x PATH
# -x ROMIO_FSTYPE_FORCE=ufs:
# -x ROMIO_HINTS=/work/0/NBB/hiraga/work/mpiio-pmembb/raw/h5bench-lustre/2024.02.19-17.34.15-default/2024.02.19-17.51.34-174276.nqsv-2/romio_hints
# -mca hook_pmembb_enable false
# -mca io romio341
# -mca osc ucx
# -mca pml ucx
# -mca osc_ucx_acc_single_intrinsic true
# -np 64
# -map-by ppr:32:node
# /home/NBB/hiraga/.cache/spack/opt/spack/linux-ubuntu20.04-icelake/gcc-11.4.0/h5bench-1.4-pmembb-l2gsbnzbjcjvcgg5vufqtrbfdzh5qkqm/bin//h5bench_write
# /work/0/NBB/hiraga/work/mpiio-pmembb/backend/h5bench-lustre/2024.02.19-17.51.34-174276.nqsv-2/0/storage/967fc1bf-0:174276.nqsv/h5bench.cfg
# /work/0/NBB/hiraga/work/mpiio-pmembb/backend/h5bench-lustre/2024.02.19-17.51.34-174276.nqsv-2/0/storage/rw.h5
# )
