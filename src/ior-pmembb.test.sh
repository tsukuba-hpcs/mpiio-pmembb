#!/bin/bash
set -eu

spack env activate mpiio-pmembb-debug

# source "../common.sh"

NNODES=$(wc --lines "${PBS_NODEFILE}" | awk '{print $1}')

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"

# librpmbb_c.so
LD_PRELOAD=$(spack location -i rpmbb)/lib/rpmbb_c/librpmbb_c.so
PMEM_PATH=/dev/dax0.0
PMEM_SIZE=0

ppn_list=(
  # 48 32 16 8 4 2 1
  # 48
  2
)

min_io_size_per_proc=$((4 * 2 ** 20))

segment_count_list=(
  1
  # 128
)

xfer_size_list=(
  2M
  # 1M
  # 512K 256K 128K 64K 32K 16K 8K 4K 2K 1K
  # 512 256
)

cmd_dropcaches=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -np "$NNODES"
  -map-by ppr:1:node
  dropcaches 3
)

max_stripe_count=2000
stripe_size=$((2*2**20)) # 2MiB fixed

runid=1
for ppn in "${ppn_list[@]}"; do
  np=$((NNODES * ppn))
  # stripe_count=$np
  # if [ $stripe_count -gt $max_stripe_count ]; then
  #   stripe_count=$max_stripe_count
  # fi

  for segment_count in "${segment_count_list[@]}"; do
    for xfer_size_human in "${xfer_size_list[@]}"; do
      xfer_size=$(numfmt --from=iec "$xfer_size_human")
      block_size=$(((min_io_size_per_proc + segment_count - 1) / segment_count))

      cmd_mpirun=(
        mpirun
        "${nqsii_mpiopts_array[@]}"
        -x PATH
        -x LD_PRELOAD="${LD_PRELOAD}"
        -x ROMIO_FSTYPE_FORCE=pmembb:
        -x ROMIO_PRINT_HINTS=1
        -mca hook_pmembb_pmem_path "${PMEM_PATH}"
        -mca hook_pmembb_pmem_size "${PMEM_SIZE}"
        -mca io romio341
        -mca hook_comm_method_display mpi_init
        -mca osc ucx
        -mca osc_ucx_acc_single_intrinsic true
        -mca pml ucx
        -mca pml_ucx_tls any
        -np "$np"
        -map-by "ppr:${ppn}:node"
      )

      cmd_ior=(
        ior
        -a MPIIO
        # --posix.odirect
        -l timestamp   # --data
        -g             # intraTestBarriers – use barriers between open, write/read, and close
        -G -1401473791 # setTimeStampSignature – set value for time stamp signature
        -k             # keepFile – don’t remove the test file(s) on program exit
        -e             # fsync
        -i 1
        -s "$segment_count"
        -b "$block_size"
        -t "$xfer_size"
        -o ./test_file
        # -O "summaryFormat=JSON"
        # -O "summaryFile=${JOB_OUTPUT_DIR}/ior_summary_${runid}.json"
      )


      cmd_write=(
        "${cmd_mpirun[@]}"
        -mca hook_pmembb_load false
        -mca hook_pmembb_save true
        "${cmd_ior[@]}"
        -w
      )

      cmd_read=(
        "${cmd_mpirun[@]}"
        -mca hook_pmembb_load true
        -mca hook_pmembb_save false
        "${cmd_ior[@]}"
        -r
        -C
        -Q 1
      )

      # export ROMIO_FSTYPE_FORCE=pmembb:
      # export LD_PRELOAD=$(spack location -i rpmbb)/lib/rpmbb_c/librpmbb_c.so
      # export OMPI_MCA_io=romio341

      # "${cmd_ior[@]}" -w
      # return

      # write
      echo "${cmd_write[@]}"
      "${cmd_write[@]}"

      # read
      echo "${cmd_read[@]}"
      "${cmd_read[@]}"

      runid=$((runid + 1))
    done
  done
done
