#!/usr/bin/bash
set -eu

np=4
ppn=2
segment_count=1
block_size=4K
xfer_size=1k
test_file="./ior_testfile"

ROMIO_HINTS="$(pwd)/ior/romio_hints/off"

IFS=" " read -r -a nqsii_mpiopts_array <<<"$NQSII_MPIOPTS"

cmd_mpirun=(
  mpirun
  "${nqsii_mpiopts_array[@]}"
  -x PATH
  -x ROMIO_FSTYPE_FORCE=testfs:
  -x ROMIO_HINTS="${ROMIO_HINTS}"
  # -x ROMIO_PRINT_HINTS=1
  -mca hook_pmembb_enable false 
  -mca io romio341
  -mca osc ucx
  # -mca pml ucx
  # --mca pml_ucx_tls any
  -mca osc_ucx_acc_single_intrinsic true
  -np "$np"
  -map-by "ppr:${ppn}:node"
)

cmd_ior=(
  ior
  -a MPIIO
  --mpiio.useStridedDatatype
  --mpiio.useFileView
  -l timestamp   # --data
  -g             # intraTestBarriers – use barriers between open, write/read, and close
  -G -1401473791 # setTimeStampSignature – set value for time stamp signature
  -k # keepFile – don’t remove the test file(s) on program exit
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


echo "${cmd_mpirun[@]}" "${cmd_ior[@]}" -w -r
"${cmd_mpirun[@]}" "${cmd_ior[@]}" -w -r

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
