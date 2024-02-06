#!/usr/bin/bash
set -eu

source ./common.sh
spack env activate mpiio-pmembb

NNODES=$(wc --lines "${PBS_NODEFILE}" | awk '{print $1}')
# NNODES=1
ppn=2
np=$((NNODES * ppn))


# export OMPI_MCA_io=romio341
# export OMPI_MCA_hook_pmembb_enable=false
# export OMPI_MCA_hook_pmembb_pmem_path=/tmp/pmem_dev
# export OMPI_MCA_hook_pmembb_pmem_size=$((ppn * 4 * 1024 ** 2))
# export ROMIO_PRINT_HINTS=0
# export ROMIO_FSTYPE_FORCE=testfs:
ROMIO_HINTS="$(this_directory)/romio_hints/off"
LD_PRELOAD=$(spack location -i rpmbb)/lib/rpmbb_c/librpmbb_c.so

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"
args_mpirun_common=(
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  -x LD_PRELOAD="${LD_PRELOAD}"
  -x ROMIO_FSTYPE_FORCE=pmembb:
  -x ROMIO_HINTS="${ROMIO_HINTS}"
  # -x ROMIO_PRINT_HINTS=1
  -mca hook_pmembb_enable true
  -mca hook_pmembb_pmem_path "/dev/dax0.0"
  # -mca hook_pmembb_pmem_size "${PMEM_SIZE}"
  -mca io romio341
  -mca osc ucx
  -mca osc_ucx_acc_single_intrinsic true
  -np "$np"
  -map-by "ppr:${ppn}:node"
)

args_mpirun_write=(
  "${args_mpirun_common[@]}"
  -mca hook_pmembb_load false
  -mca hook_pmembb_save true
)
args_mpirun_read=(
  "${args_mpirun_common[@]}"
  -mca hook_pmembb_load true
  -mca hook_pmembb_save false
)
args_mpirun_meta=(
  "${args_mpirun_common[@]}"
  -mca hook_pmembb_load false
  -mca hook_pmembb_save false
)

export MPI_ARGS
export TEST_DIR
TEST_DIR=.
MPI_ARGS="${args_mpirun_write[*]}"
envsubst < workflows/write.json > wf-write.json
MPI_ARGS="${args_mpirun_read[*]}"
envsubst < workflows/read.json > wf-read.json

export META_PROC_ROWS
export META_PROC_COLS
META_PROC_ROWS=2
META_PROC_COLS=2
MPI_ARGS="${args_mpirun_meta[*]}"
envsubst < workflows/meta.json > wf-meta.json

# envsubst < workflows/meta.json > workflow-write.json

# h5bench wf-write.json
# h5bench wf-read.json
h5bench wf-meta.json

# envsubst < workflows/cs-write.json > workflow-write.json
# envsubst < workflows/cs-read.json > workflow-read.json
# envsubst < workflows/prl-write.json > workflow-write.json
# h5bench workflow-write.json
# h5bench workflow-read.json

# cmd_run=(
#   "${cmd_mpirun[@]}"
#   "${cmd_h5bench[@]}"
# )

# echo "${cmd_run[@]}"
# "${cmd_run[@]}"
