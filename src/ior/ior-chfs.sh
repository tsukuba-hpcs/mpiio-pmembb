#!/bin/bash
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE:-$0}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/common.sh"
TIMESTAMP="$(timestamp)"

# default params 
: ${ELAPSTIM_REQ:="3:00:00"}
: ${LABEL:=default}

JOB_FILE="$(remove_ext "$(this_file)").job.sh"
PROJECT_ROOT="$(to_fullpath "$(this_directory)/../..")"
OUTPUT_DIR="$PROJECT_ROOT/raw/$(remove_ext "$(this_file_name)")/${TIMESTAMP}-${LABEL}"
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

nnodes_list=(
  # 32 64
  1 2 4 8 16 32 64 #100 # 120
  # 4
  # 100
  # 16
  # 100 64 32
  # 16 32 64
  # 16
  # 16 8 4 2 1
  # 41 42 # ppn48: -C 2000
  # 56 57 # ppn48: -C 2727
)
niter=1

param_set_list=(
  "
  SPACK_ENV_NAME=chfs
  "
)

for nnodes in "${nnodes_list[@]}"; do
  for ((iter=0; iter<niter; iter++)); do
    for param_set in "${param_set_list[@]}"; do
      eval "$param_set"

      cmd_qsub=(
        # qsub_lustre
        qsub
        -A NBBG
        # -A NBB
        -q "$(determine_queue "${nnodes}")"
        # -q gpu_low
        -l elapstim_req="${ELAPSTIM_REQ}"
        -T distrib 
        -b "$nnodes"
        -v USE_DEVDAX=pmemkv
        -v NUM_DEVDAX=1
        -v OUTPUT_DIR="$OUTPUT_DIR"
        -v SCRIPT_DIR="$SCRIPT_DIR"
        -v LABEL="$LABEL"
        -v SPACK_ENV_NAME="$SPACK_ENV_NAME"
        "${JOB_FILE}"
      )
      echo "${cmd_qsub[@]}"
      "${cmd_qsub[@]}"
    done
  done
done
