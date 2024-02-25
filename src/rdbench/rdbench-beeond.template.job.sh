#!/bin/bash
#------- qsub option -----------
#PBS -A NBBG
#PBS -l elapstim_req=24:00:00
#PBS -T openmpi
#PBS -v NQSV_MPI_VER=${NQSV_MPI_VER}
#PBS -v USE_PMEM_BEEOND=1
#------- Program execution -----------
set -eu

module load use.own
module load "openmpi/$NQSV_MPI_VER"

# Requires
# - SPACK_ENV_NAME
# - SCRIPT_DIR
# - OUTPUT_DIR

: ${RDBENCH_STEPS:=640}
: ${RDBENCH_INTERVAL:=64}

spack env activate "${SPACK_ENV_NAME}"

source "$SCRIPT_DIR/common.sh"
exec 1> >(addtimestamp)
exec 2> >(addtimestamp >&2)

JOB_START=$(timestamp)
NNODES=$(wc --lines "${PBS_NODEFILE}" | awk '{print $1}')
JOBID=$(echo "$PBS_JOBID" | cut -d : -f 2)
JOB_OUTPUT_DIR="${OUTPUT_DIR}/${JOB_START}-${JOBID}-${NNODES}"

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"

echo "prepare the output directory: ${JOB_OUTPUT_DIR}"
mkdir -p "${JOB_OUTPUT_DIR}"
cp "$0" "${JOB_OUTPUT_DIR}"
cp "${PBS_NODEFILE}" "${JOB_OUTPUT_DIR}"
printenv >"${JOB_OUTPUT_DIR}/env.txt"

# romio_hints
ROMIO_HINTS="${JOB_OUTPUT_DIR}/romio_hints"
cp "${SCRIPT_DIR}/romio_hints/off" "${ROMIO_HINTS}"

save_job_params() {
  cat <<EOS >"${JOB_OUTPUT_DIR}"/job_params_${runid}.json
{
  "nnodes": ${NNODES},
  "ppn": ${ppn},
  "np": ${np},
  "jobid": "$JOBID",
  "runid": ${runid},
  "lustre_version": "$(lfs --version | awk '{print $2}')",
  "spack_env_name": "${SPACK_ENV_NAME}",
  "storageSystem": "BeeOND"
}
EOS
}

ppn_list=(
  36
  48
)


# workflow_id=0
runid=0
for ppn in "${ppn_list[@]}"; do
  np=$((NNODES * ppn))
  rdbench_length_per_node=$((48 * 2 ** 10)) # 48k * 48k * sizeof(double) = 18 GiB/node
  rdbench_length=$((rdbench_length_per_node * $(sqrt "$NNODES")))

  cmd_mpirun=(
    mpirun
    "${nqsii_mpiopts_array[@]}"
    -x PATH
    -x ROMIO_FSTYPE_FORCE=ufs:
    -x ROMIO_HINTS="${ROMIO_HINTS}"
    -mca hook_pmembb_enable false
    -mca io romio341
    -mca osc ucx
    -mca osc_ucx_acc_single_intrinsic true
    -np "$np"
    -map-by "ppr:${ppn}:node"
  )

  cmd_rdbench=(
    rdbench
    --length "$rdbench_length"
    --output "/beeond/o_"
    --nomkdir
    --iotype view
    --steps "$RDBENCH_STEPS"
    --interval "$RDBENCH_INTERVAL"
    --novalidate
    --disable-initial-output
    --prettify
    --xnp $((6 * $(sqrt "$NNODES")))
    --nosync
  )

  cmd_dropcaches=(
    mpirun
    "${nqsii_mpiopts_array[@]}"
    -np "$NNODES"
    -map-by ppr:1:node
    dropcaches 3
  )

  cmd_benchmark=(
    time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
    "${cmd_mpirun[@]}"
    "${cmd_rdbench[@]}"
  )

  save_job_params

  # dropcaches
  echo "${cmd_dropcaches[@]}"
  "${cmd_dropcaches[@]}"

  # rdbench
  echo "${cmd_benchmark[@]}"
  "${cmd_benchmark[@]}" \
    > >(tee "${JOB_OUTPUT_DIR}/rdbench_stdout_${runid}.json") \
    2> >(tee "${JOB_OUTPUT_DIR}/rdbench_stderr_${runid}.txt" >&2)

  # dump test dir
  tree -s /beeond >"${JOB_OUTPUT_DIR}/out_tree_${ppn}"

  rm /beeond/*

  sleep 5

  runid=$((runid + 1))
done
