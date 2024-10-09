#!/usr/bin/bash
set -eu

np=4
ppn=2
test_file="./tile_testfile"

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

cmd_tile=(
  "${cmd_mpirun[@]}"
  mpi-tile-io
    --filename "$test_file"
    --nr_tiles_x 2
    --nr_tiles_y 2
    --sz_tile_x 1024
    --sz_tile_y 2
    --sz_element 8
    --overlap_x 0
    --overlap_y 0
    --collective
)

echo "${cmd_tile[@]}"
"${cmd_tile[@]}"


# echo "${cmd_mpirun[@]}" "${cmd_ior[@]}" -w -r
# "${cmd_mpirun[@]}" "${cmd_ior[@]}" -w -r

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
