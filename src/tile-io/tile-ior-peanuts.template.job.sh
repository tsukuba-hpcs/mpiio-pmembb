#!/bin/bash
#------- qsub option -----------
#PBS -A NBBG
#PBS -l elapstim_req=3:00:00
#PBS -T openmpi
#PBS -v NQSV_MPI_VER=${NQSV_MPI_VER}
#PBS -v USE_DEVDAX=pmemkv
#PBS -v NUM_DEVDAX=1
#------- Program execution -----------
set -eu

module purge
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



ppn=36
np=$((NNODES*ppn))
IFS=$' \t\n' read tile_np_x tile_np_y <<< "$(dims_create_2d "${np}")"
tile_elem_size=8
tile_nelem_x=$((8*2**10)) # 8K * 8 = 64KB
tile_nelem_y=1

ior_segment_count=1
ior_block_size=$((tile_nelem_x * tile_nelem_y * tile_elem_size))
ior_xfer_size=$((tile_np_x * tile_nelem_x * tile_elem_size))


rdbench_length_per_node=$((48*2**10)) # 48k * 48k * sizeof(double) = 18 GiB/node
rdbench_length=$((rdbench_length_per_node * $(sqrt "$NNODES")))

ior_segment_count=1
ior_block_size=$((rdbench_length_per_node * rdbench_length_per_node * 8 / ppn))
ior_xfer_size=$((rdbench_length * 8)) # 48k * 8node (for 64nodes job) * sizeof(double) = 3M = x方向の長さ


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
  -mca osc_ucx_acc_single_intrinsic true
  -np "$np"
  -map-by "ppr:${ppn}:node"
)

cmd_rdbench=(
  rdbench
  --length "$rdbench_length"
  --output "${JOB_BACKEND_DIR}/o_"
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

# max_stripe_count=2000
stripe_size=$((2*2**20)) # 2MiB fixed
stripe_count=1

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
  "ior_segment_count": $ior_segment_count,
  "ior_block_size": $ior_block_size,
  "ior_xfer_size": $ior_xfer_size
}
EOS
}

# workflow_id=0
runid=0

test_dir="$JOB_BACKEND_DIR"

save_job_params

cmd_lfs_setstripe=(
  lfs setstripe
  -C "$stripe_count"
  --stripe-index -1
  --stripe-size "${stripe_size}"
  "${test_dir}"
)
"${cmd_lfs_setstripe[@]}"
lfs getstripe "${test_dir}"

# dropcaches
echo "${cmd_dropcaches[@]}"
"${cmd_dropcaches[@]}"

# rdbench
cmd_benchmark=(
  time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
  "${cmd_mpirun[@]}"
  -mca hook_pmembb_load false
  -mca hook_pmembb_save true
  "${cmd_rdbench[@]}"
)

echo "${cmd_benchmark[@]}"
"${cmd_benchmark[@]}" \
  > >(tee "${JOB_OUTPUT_DIR}/rdbench_stdout_${runid}.json") \
  2> >(tee "${JOB_OUTPUT_DIR}/rdbench_stderr_${runid}.txt" >&2)

# dump test dir
tree -s "${JOB_BACKEND_DIR}" > "${JOB_OUTPUT_DIR}/out_tree"

## find test_file
test_file=$(find "${test_dir}" -name "o_*.bin" | sort -n | head -1)

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


for ((iter=0; iter<2; iter+=1)); do
  # ior
  runid=$((runid + 1))

  save_job_params

  # dropcaches
  echo "${cmd_dropcaches[@]}"
  "${cmd_dropcaches[@]}"

  cmd_segmented_read=(
    time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
    "${cmd_mpirun[@]}"
    -mca hook_pmembb_load true
    -mca hook_pmembb_save true
    "${cmd_ior[@]}"
    -O "summaryFile=${JOB_OUTPUT_DIR}/ior_summary_${runid}.json"
    -r
    -s "$ior_segment_count"
    -b "$ior_block_size"
    -t "$ior_xfer_size"
  )

  echo "${cmd_segmented_read[@]}"
  "${cmd_segmented_read[@]}" \
    > "${JOB_OUTPUT_DIR}/ior_stdout_${runid}.txt" \
    2> "${JOB_OUTPUT_DIR}/ior_stderr_${runid}.txt"
done
