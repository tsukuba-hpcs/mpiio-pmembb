#!/bin/bash
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE:-$0}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/common.sh"
TIMESTAMP="$(timestamp)"

# default params 
: ${ELAPSTIM_REQ:="1:00:00"}
: ${LABEL:=default}
# : ${NQSV_MPI_VER:="5.0.0rc12-pmembb-gcc-11.4.0-u6s35fd"}

JOB_FILE="$(remove_ext "$(this_file)").job.sh"
JOB_TEMPLATE_FILE="$(remove_ext "$(this_file)").template.job.sh"
PROJECT_ROOT="$(to_fullpath "$(this_directory)/../..")"
OUTPUT_DIR="$PROJECT_ROOT/raw/$(remove_ext "$(this_file_name)")/${TIMESTAMP}-${LABEL}"
BACKEND_DIR="$PROJECT_ROOT/backend/$(remove_ext "$(this_file_name)")"
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"
mkdir -p "${BACKEND_DIR}"

nnodes_list=(
  1 2 4 8 16 32
  # 100
  # 16
  # 1 2 4 8 16 32 64 #100 120
  # 16
  # 32 64
  # 4
  # 16
  # 16 8 4 2 1
  # 41 42 # ppn48: -C 2000
  # 56 57 # ppn48: -C 2727
)
niter=2

param_set_list=(
  "
  SPACK_ENV_NAME=mpiio-pmembb
  NQSV_MPI_VER=5.0.0rc12-pmembb-eval-gcc-11.4.0-r5rhxc6
  "
  "
  SPACK_ENV_NAME=mpiio-pmembb-deferred-open
  NQSV_MPI_VER=5.0.0rc12-pmembb-eval-gcc-11.4.0-fevlzaz
  "
  # "
  # SPACK_ENV_NAME=mpiio-pmembb-agg-read
  # NQSV_MPI_VER=5.0.0rc12-pmembb-eval-gcc-11.4.0-r5rhxc6
  # "
  # "
  # SPACK_ENV_NAME=mpiio-pmembb-no-optim
  # NQSV_MPI_VER=5.0.0rc12-pmembb-eval-gcc-11.4.0-fevlzaz
  # "
  # "
  # SPACK_ENV_NAME=mpiio-pmembb-profile
  # NQSV_MPI_VER=5.0.0rc12-pmembb-eval-gcc-11.4.0-r5rhxc6
  # "
)

for nnodes in "${nnodes_list[@]}"; do
  for ((iter=0; iter<niter; iter++)); do
    for param_set in "${param_set_list[@]}"; do
      eval "$param_set"

      # generate job file
      export NQSV_MPI_VER
      envsubst < "${JOB_TEMPLATE_FILE}" '$NQSV_MPI_VER' > "$JOB_FILE"

      cmd_qsub=(
        # qsub_lustre
        qsub
        # -A NBBG
        -A NBB
        # -q "$(determine_queue "${nnodes}")"
        -q gpu_low
        -l elapstim_req="${ELAPSTIM_REQ}"
        -T openmpi
        -v NQSV_MPI_VER="${NQSV_MPI_VER}"
        -b "$nnodes"
        -v USE_DEVDAX=pmemkv
        -v NUM_DEVDAX=1
        -v OUTPUT_DIR="$OUTPUT_DIR"
        -v SCRIPT_DIR="$SCRIPT_DIR"
        -v BACKEND_DIR="$BACKEND_DIR"
        -v LABEL="$LABEL"
        -v SPACK_ENV_NAME="$SPACK_ENV_NAME"
        "${JOB_FILE}"
      )
      echo "${cmd_qsub[@]}"
      "${cmd_qsub[@]}"
    done
  done
done
