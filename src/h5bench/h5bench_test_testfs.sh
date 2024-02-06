#!/usr/bin/bash
set -eu

source ./common.sh
spack env activate mpiio-pmembb-debug

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

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"
args_mpirun=(
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  # -x LD_PRELOAD="${LD_PRELOAD}"
  -x ROMIO_FSTYPE_FORCE=testfs:
  -x ROMIO_HINTS="${ROMIO_HINTS}"
  -mca hook_pmembb_enable false
  # -mca hook_pmembb_pmem_path "${PMEM_PATH}"
  # -mca hook_pmembb_pmem_size "${PMEM_SIZE}"
  -mca io romio341
  -mca osc ucx
  -mca osc_ucx_acc_single_intrinsic true
  -np "$np"
  -map-by "ppr:${ppn}:node"
)

MPI_ARGS="${args_mpirun[*]}"
export MPI_ARGS
envsubst < workflows/write.json > workflow-write.json
envsubst < workflows/read.json > workflow-read.json

# envsubst < workflows/meta.json > workflow-write.json

h5bench workflow-write.json
h5bench workflow-read.json

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
