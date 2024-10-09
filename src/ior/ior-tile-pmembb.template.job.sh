#!/bin/bash
#------- qsub option -----------
#PBS -A NBBG
#PBS -l elapstim_req=5:00:00
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

ppn_list=(
  # 48 32 16 8 4 2 1
  48
  # 16
)

tile_elem_size=8 # 8 Byte
tile_chunk_size_x=$((16 * 2 ** 10)) # 8 K
tile_chunk_size_y=$((512)) # 1 K
# tile_chunk_size=$((2 * 2 ** 10))
tile_io_per_proc=$((tile_chunk_size_x * tile_chunk_size_y * tile_elem_size))
# 8 K * 8 K * 8 Byte = 512 MiB/procs
# 512 MiB * 48 ppn = 24 GiB/node
# 512 MiB * 36 ppn = 18 GiB/node

write_xfer_size=$((2*2**20)) # 2 MiB

cmd_dropcaches=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -np "$NNODES"
  -map-by ppr:1:node
  dropcaches 3
)

max_stripe_count=2000
stripe_size=$((2*2**20)) # 2MiB fixed

save_job_params() {
  cat <<EOS >"${JOB_OUTPUT_DIR}"/job_params_${runid}.json
{
  "storageSystem": "PEANUTS",
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
  "tile_elem_size": ${tile_elem_size},
  "tile_chunk_size_x": ${tile_chunk_size_x},
  "tile_chunk_size_y": ${tile_chunk_size_y},
  "tile_io_per_proc": ${tile_io_per_proc},
  "tile_xnp": ${tile_xnp},
  "tile_ynp": ${tile_ynp}
}
EOS
}

workflow_id=0
runid=0
for ppn in "${ppn_list[@]}"; do
  np=$((NNODES * ppn))
  stripe_count=$np
  if [ $stripe_count -gt $max_stripe_count ]; then
    stripe_count=$max_stripe_count
  fi

  # IFS=$' \t\n' read tile_xnp tile_ynp <<< "$(dims_create_2d "${np}")"

  echo "prepare test_dir"
  test_dir="${JOB_BACKEND_DIR}/${workflow_id}"
  test_file="${test_dir}/test_file"
  mkdir -p "${test_dir}"

  cmd_lfs_setstripe=(
    lfs setstripe
    -C "$stripe_count"
    --stripe-index -1
    --stripe-size "${stripe_size}"
    "${test_dir}"
  )
  stripe_count=1
  #"${cmd_lfs_setstripe[@]}"
  lfs getstripe "${test_dir}"

  cmd_mpirun=(
    mpirun
    "${nqsii_mpiopts_array[@]}"
    -x PATH
    -x LD_PRELOAD="${LD_PRELOAD}"
    -x ROMIO_FSTYPE_FORCE=pmembb:
    -x ROMIO_HINTS="${ROMIO_HINTS}"
    # -x UCX_IB_REG_METHODS="odp,direct"
    # -x UCX_TLS=dc
    -mca hook_pmembb_pmem_path "${PMEM_PATH}"
    -mca hook_pmembb_pmem_size "${PMEM_SIZE}"
    -mca io romio341
    -mca osc ucx
    -mca pml ucx
    -mca osc_ucx_tls rc_mlx5
    # --mca pml_ucx_tls any
    -mca osc_ucx_acc_single_intrinsic true
    # -mca osc_ucx_outstanding_ops_flush_threshold 1024
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
    -s 1
    -b "$tile_io_per_proc"
    -t "$write_xfer_size"
    -o "$test_file"
    -O "summaryFormat=JSON"
  )

  # dropcaches
  echo "${cmd_dropcaches[@]}"
  "${cmd_dropcaches[@]}"

  # segmented write
  cmd_write=(
    time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
    "${cmd_mpirun[@]}"
    -mca hook_pmembb_load false
    -mca hook_pmembb_save true
    "${cmd_ior[@]}"
    # -O "stoneWallingStatusFile=${JOB_OUTPUT_DIR}/ior_stonewall_${runid}"
    -O "summaryFile=${JOB_OUTPUT_DIR}/ior_summary_${runid}.json"
    -w
  )

  echo "${cmd_write[@]}"
  "${cmd_write[@]}" \
    > "${JOB_OUTPUT_DIR}/ior_stdout_${runid}.txt" \
    2> "${JOB_OUTPUT_DIR}/ior_stderr_${runid}.txt"

  runid=$((runid + 1))

  for ((tile_ynp=1; tile_ynp<=NNODES; tile_ynp*=2)); do
    tile_xnp=$((np / tile_ynp))

    cmd_tile=(
      mpi-tile-io
        --filename "$test_file"
        --nr_tiles_x "$tile_xnp"
        --nr_tiles_y "$tile_ynp"
        --sz_tile_x "$tile_chunk_size_x"
        --sz_tile_y "$tile_chunk_size_y"
        --sz_element "$tile_elem_size"
        --overlap_x 0
        --overlap_y 0
        --collective
    )

    # mpi-tile-io read
    cmd_read=(
      time_json -o "${JOB_OUTPUT_DIR}/time_${runid}.json"
      "${cmd_mpirun[@]}"
      -mca hook_pmembb_load true
      -mca hook_pmembb_save true
      "${cmd_tile[@]}"
    )

    save_job_params

    # dropcaches
    echo "${cmd_dropcaches[@]}"
    "${cmd_dropcaches[@]}"

    echo "${cmd_read[@]}"
    "${cmd_read[@]}" \
      > "${JOB_OUTPUT_DIR}/tile_stdout_${runid}.txt" \
      2> "${JOB_OUTPUT_DIR}/tile_stderr_${runid}.txt"

    runid=$((runid + 1))
  done
  workflow_id=$((workflow_id + 1))
done
