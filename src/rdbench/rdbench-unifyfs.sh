#!/bin/bash
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE:-$0}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/common.sh"
TIMESTAMP="$(timestamp)"

# default params 
: ${ELAPSTIM_REQ:="1:00:00"}
: ${LABEL:=default}

JOB_FILE="$(remove_ext "$(this_file)").job.sh"
PROJECT_ROOT="$(to_fullpath "$(this_directory)/../..")"
OUTPUT_DIR="$PROJECT_ROOT/raw/$(remove_ext "$(this_file_name)")/${TIMESTAMP}-${LABEL}"
BACKEND_DIR="$PROJECT_ROOT/backend/$(remove_ext "$(this_file_name)")"
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"
mkdir -p "${BACKEND_DIR}"

nnodes_list=(
  # 1 4 9 16 25 36 49 64
  64 49 36 25 16 9 4 1
  # 36 49
  # 4
)
niter=1

param_set_list=(
  "
  SPACK_ENV_NAME=unifyfs
  "
)

for nnodes in "${nnodes_list[@]}"; do
  for ((iter=0; iter<niter; iter++)); do
    for param_set in "${param_set_list[@]}"; do
      eval "$param_set"

      cmd_qsub=(
        # qsub_lustre
        qsub
        # -A NBBG
        -A NBB
        # -q "$(determine_queue "${nnodes}")"
        -q gpu_low
        -l elapstim_req="${ELAPSTIM_REQ}"
        -T openmpi 
        -v NQSV_MPI_VER=4.1.5/gcc11.4.0-cuda12.1.0
        -b "$nnodes"
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
