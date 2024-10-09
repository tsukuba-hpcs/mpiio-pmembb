#!/bin/bash

RANK=0
_mode="nop"
_all=0

while [[ $# -gt 0 ]]; do
        case $1 in
                --prefix|-p)
                        OUTPUT_PREFIX="$2"
                        shift
                        shift
                        ;;
                --rank|-r)
                        RANK="$2"
                        shift
                        shift
                        ;;
                --all)
                        _all=1
                        shift
                        ;;
                *)
                        break
                        ;;
        esac
done

OUTPUT_PATH="${OUTPUT_PREFIX}perf.data.${PMI_RANK}"

set -x
if [ "${PMI_RANK}" == "${RANK}" ]; then
        perf record -a --call-graph dwarf -F 99 -o "${OUTPUT_PATH}" "$@"
        perf script -i "${OUTPUT_PATH}" > "${OUTPUT_PATH}.out"
        ${HOME}/FlameGraph/stackcollapse-perf.pl "${OUTPUT_PATH}.out" \
                > "${OUTPUT_PATH}.out.folded"
        ${HOME}/FlameGraph/flamegraph.pl "${OUTPUT_PATH}.out.folded" \
                > "${OUTPUT_PREFIX}flamegraph.${PMI_RANK}.html"
elif [ $_all -eq 1 ]; then
        perf record -a --call-graph dwarf -F 99 -o "${OUTPUT_PATH}" "$@"
        perf script -i "${OUTPUT_PATH}" > "${OUTPUT_PATH}.out"
        ${HOME}/FlameGraph/stackcollapse-perf.pl "${OUTPUT_PATH}.out" \
                > "${OUTPUT_PATH}.out.folded"
        ${HOME}/FlameGraph/flamegraph.pl "${OUTPUT_PATH}.out.folded" \
                > "${OUTPUT_PREFIX}flamegraph.${PMI_RANK}.html"
else
        "$@"
fi
set +x
