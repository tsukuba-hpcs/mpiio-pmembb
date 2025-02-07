#!/bin/bash
#------- qsub option -----------
#PBS -A NBBG
#PBS -l elapstim_req=2:00:00
#PBS -T openmpi
#PBS -v NQSV_MPI_VER=${NQSV_MPI_VER}
#PBS -v USE_DEVDAX=pmemkv
#PBS -v NUM_DEVDAX=1
#------- Program execution -----------
set -eu

module load use.own
module load "openmpi/$NQSV_MPI_VER"

# Requires
# - SPACK_ENV_NAME
# - SCRIPT_DIR
# - OUTPUT_DIR
# - BACKEND_DIR

spack env activate "${SPACK_ENV_NAME}"

source "$SCRIPT_DIR/common.sh"
exec 1> >(addtimestamp)
exec 2> >(addtimestamp >&2)

JOB_START=$(timestamp)
NNODES=$(wc --lines "${PBS_NODEFILE}" | awk '{print $1}')
JOBID=$(echo "$PBS_JOBID" | cut -d : -f 2)
JOB_OUTPUT_DIR="${OUTPUT_DIR}/${JOB_START}-${JOBID}-${NNODES}"
JOB_BACKEND_DIR="${BACKEND_DIR}/$(basename -- "${JOB_OUTPUT_DIR}")"

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"

# librpmbb_c.so
LD_PRELOAD=$(spack location -i rpmbb)/lib/rpmbb_c/librpmbb_c.so
PMEM_PATH=/dev/dax0.0
PMEM_SIZE=0

echo "prepare the output directory: ${JOB_OUTPUT_DIR}"
mkdir -p "${JOB_OUTPUT_DIR}"
cp "$0" "${JOB_OUTPUT_DIR}"
cp "${PBS_NODEFILE}" "${JOB_OUTPUT_DIR}"
printenv >"${JOB_OUTPUT_DIR}/env.txt"

# romio_hints
ROMIO_HINTS="${JOB_OUTPUT_DIR}/romio_hints"
cp "${SCRIPT_DIR}/romio_hints/off" "${ROMIO_HINTS}"

echo "prepare backend dir: ${JOB_BACKEND_DIR}"
mkdir -p "${JOB_BACKEND_DIR}"
trap 'rm -rf "${JOB_BACKEND_DIR}" ; exit 1' 1 2 3 15
trap 'rm -rf "${JOB_BACKEND_DIR}" ; exit 0' EXIT

cmd_dropcaches=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -np "$NNODES"
  -map-by ppr:1:node
  dropcaches 3
)

max_stripe_count=2000
stripe_size=$((2 * 2 ** 20)) # 2MiB fixed

save_job_params() {
  cat <<EOS >"${JOB_OUTPUT_DIR}"/job_params_${runid}.json
{
  "nnodes": ${NNODES},
  "ppn": ${ppn},
  "np": ${np},
  "jobid": "$JOBID",
  "runid": ${runid},
  "pmem_path": "${PMEM_PATH}",
  "pmem_size": ${PMEM_SIZE},
  "lustre_version": "$(lfs --version | awk '{print $2}')",
  "lustre_stripe_size": ${stripe_size},
  "lustre_stripe_count": ${stripe_count},
  "spack_env_name": "${SPACK_ENV_NAME}",
  "storageSystem": "PEANUTS",
  "ior_w_segment_count": $ior_w_segment_count,
  "ior_w_block_size": $ior_w_block_size,
  "ior_w_xfer_size": $ior_w_xfer_size,
  "ior_r_segment_count": $ior_r_segment_count,
  "ior_r_block_size": $ior_r_block_size,
  "ior_r_xfer_size": $ior_r_xfer_size
}
EOS
}

ppn=8
np=$((NNODES * ppn))

ior_w_segment_count=$((128 * 2 ** 10))
ior_w_block_size=$((4 * 2 ** 10))
ior_w_xfer_size=$ior_w_block_size

ior_r_segment_count=1
ior_r_block_size=$((ior_w_segment_count * ior_w_block_size))
ior_r_xfer_size=$((512 * ior_w_block_size))

stripe_count=$np
if [ $stripe_count -gt $max_stripe_count ]; then
  stripe_count=$max_stripe_count
fi

workflow_id=0
runid=0

echo "prepare test_dir"
test_dir="${JOB_BACKEND_DIR}/${workflow_id}"
test_file="${test_dir}/test_file"
mkdir -p "${test_dir}"

stripe_count=1
cmd_lfs_setstripe=(
  lfs setstripe
  # -C "$stripe_count"
  --stripe-index -1
  --stripe-size "${stripe_size}"
  "${test_dir}"
)
# "${cmd_lfs_setstripe[@]}"
lfs getstripe "${test_dir}"

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  -x LD_PRELOAD="${LD_PRELOAD}"
  -x ROMIO_FSTYPE_FORCE=pmembb:
  -x ROMIO_HINTS="${ROMIO_HINTS}"
  -mca hook_pmembb_pmem_path "${PMEM_PATH}"
  -mca hook_pmembb_pmem_size "${PMEM_SIZE}"
  -mca io romio341
  -mca osc ucx
  -mca osc_ucx_tls rc_mlx5
  # -mca pml ucx
  -mca osc_ucx_acc_single_intrinsic true
  -np "$np"
  -map-by "ppr:${ppn}:node"
)

cmd_ior=(
  ior
  -a MPIIO
  -l timestamp   # --data
  -g             # intraTestBarriers – use barriers between open, write/read, and close
  -G -1401473791 # setTimeStampSignature – set value for time stamp signature
  -k             # keepFile – don’t remove the test file(s) on program exit
  -e             # fsync
  -o "$test_file"
  -O "summaryFormat=JSON"
)

# write

save_job_params

# dropcaches
echo "${cmd_dropcaches[@]}"
"${cmd_dropcaches[@]}"

# write
cmd_write=(
  time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
  "${cmd_mpirun[@]}"
  -mca hook_pmembb_load false
  -mca hook_pmembb_save true
  "${cmd_ior[@]}"
  -i 1
  -s "$ior_w_segment_count"
  -b "$ior_w_block_size"
  -t "$ior_w_xfer_size"
  -O "summaryFile=${JOB_OUTPUT_DIR}/ior_summary_${runid}.json"
  -w
)

echo "${cmd_write[@]}"
"${cmd_write[@]}" \
  >"${JOB_OUTPUT_DIR}/ior_stdout_${runid}.txt" \
  2>"${JOB_OUTPUT_DIR}/ior_stderr_${runid}.txt"


for ((iter=0; iter<2; iter+=1)); do
  runid=$((runid + 1))

  # read segmented
  save_job_params

  # dropcaches
  echo "${cmd_dropcaches[@]}"
  "${cmd_dropcaches[@]}"

  cmd_read_segmented=(
    time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
    "${cmd_mpirun[@]}"
    -mca hook_pmembb_load true
    -mca hook_pmembb_save true
    "${cmd_ior[@]}"
    -i 1
    -s "$ior_r_segment_count"
    -b "$ior_r_block_size"
    -t "$ior_r_xfer_size"
    -O "summaryFile=${JOB_OUTPUT_DIR}/ior_summary_${runid}.json"
    -r
  )

  echo "${cmd_read_segmented[@]}"
  "${cmd_read_segmented[@]}" \
    >"${JOB_OUTPUT_DIR}/ior_stdout_${runid}.txt" \
    2>"${JOB_OUTPUT_DIR}/ior_stderr_${runid}.txt"

done

runid=$((runid + 1))
workflow_id=$((workflow_id + 1))
