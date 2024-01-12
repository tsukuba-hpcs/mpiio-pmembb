#!/usr/bin/bash
set -eu

np=4
ppn=2
segment_count=1
block_size=8K
xfer_size=4k
test_file="./ior_testfile"

export LD_PRELOAD=$(spack location -i rpmbb)/lib/rpmbb_c/librpmbb_c.so
export OMPI_MCA_io=romio341
export OMPI_MCA_hook_pmembb_pmem_path=/tmp/pmem_dev
export OMPI_MCA_hook_pmembb_pmem_size=$((ppn * 4 * 1024 ** 2))
# export ROMIO_PRINT_HINTS=0
export ROMIO_FSTYPE_FORCE=pmembb:
export ROMIO_HINTS="$(pwd)/romio_hints/disable_all"

cmd_mpirun=(
  mpirun
  -x PATH
  -x LD_PRELOAD
  # -x ROMIO_PRINT_HINTS=1
  -x ROMIO_FSTYPE_FORCE
  -x ROMIO_HINTS
  -mca hook_pmembb_pmem_path "$OMPI_MCA_hook_pmembb_pmem_path"
  -mca hook_pmembb_pmem_size "$OMPI_MCA_hook_pmembb_pmem_size"
  # -mca mpi_show_mca_params all
  -mca io "$OMPI_MCA_io"
  --host "$MPI_HOSTS"
  -np "$np"
  -map-by "ppr:${ppn}:node"
)

opt_pmembb_load=(
  -mca hook_pmembb_load true
)

cmd_ior=(
  ior
  -a MPIIO
  -l timestamp   # --data
  -g             # intraTestBarriers – use barriers between open, write/read, and close
  -G -1401473791 # setTimeStampSignature – set value for time stamp signature
  #-k # keepFile – don’t remove the test file(s) on program exit
  -e # fsync
  # -F # file-per-process
  -i 1
  -s "$segment_count"
  -b "$block_size"
  -t "$xfer_size"
  -o "$test_file"
  # -w
  # -D 300
  # -O "stoneWallingWearOut=1"
  # -O "stoneWallingStatusFile=${JOB_OUTPUT_DIR}/ior_stonewall_${runid}"
  # -O "summaryFormat=JSON"
  # -O "summaryFile=${JOB_OUTPUT_DIR}/ior_summary_${runid}.json"
)



echo "${cmd_mpirun[@]}" "${cmd_ior[@]}" -w -r -R
"${cmd_mpirun[@]}" "${cmd_ior[@]}" -w -r -R

# echo "${cmd_ior[@]}" -w -r -R
# "${cmd_ior[@]}" -w -r -R

# echo "${cmd_mpirun[@]}" "${opt_pmembb_load[@]}" "${cmd_ior[@]}" -r -R
# "${cmd_mpirun[@]}" "${opt_pmembb_load[@]}" "${cmd_ior[@]}" -r -R

# export OMPI_MCA_hook_pmembb_load=false
# echo "${cmd_ior[@]}" -w
# "${cmd_ior[@]}" -w

# export OMPI_MCA_hook_pmembb_load=true
# echo "${cmd_ior[@]}" -r -R -C -Q 1
# "${cmd_ior[@]}" -r -R -C -Q 1

# export LD_PRELOAD=$(spack location -i rpmbb)/lib/rpmbb_c/librpmbb_c.so
# gdb -ex run --args "${cmd_ior[@]}"
# gdb --args "${cmd_ior[@]}"
# echo "${cmd_ior[@]}"
# "${cmd_ior[@]}"
