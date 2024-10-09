#!/bin/bash

function timestamp() {
  date +%Y.%m.%d-%H.%M.%S
}
 
function addtimestamp() {
  while IFS= read -r line; do
    printf '%s %s\n' "$(date +%Y.%m.%d-%H.%M.%S)" "$line";
  done
}

function log2() {
  echo $1 | awk '{print log($1)/log(2)}'
}

function sqrt() {
  echo "$1" | awk '{print sqrt($1)}'
}

function print_var() {
  echo "$1=${!1}"
}

function to_fullpath() {
  readlink -f "$1"
}

function this_file() {
  readlink -f "$0"
}

function this_file_name() {
  basename -- "$(this_file)"
}

function this_directory() {
  dirname "$(to_fullpath "$0")"
}

function this_directory_name() {
  basename -- "$(this_directory)"
}

function remove_ext() {
  echo "${1%.*}"
}

function determine_queue() {
  local nnodes=$1
  if [[ $nnodes -lt 32 ]]; then
    echo "gen_S"
  elif [[ $nnodes -lt 64 ]]; then
    echo "gen_M"
  else
    echo "gen_L"
  fi
}

#qsubのラッパーコマンドです。--afterを自動で追加します。その他の引数はそのままqsubに渡ります。
# usage: qsub_lustre -A NBBG -q gen_S job.sh
function qsub_lustre() {
  local LAST_JOB_FILE="/work/NBB/share/lustre_last_job"
  local JOB_ID_REGEX='[0-9]+\.nqsv'
  local LAST_JOB_ID

  # /work/NBB/share/lustre_last_jobからjob IDを読み込む
  if [ -f "$LAST_JOB_FILE" ]; then
    LAST_JOB_ID=$(cat "$LAST_JOB_FILE")
  else
    echo "Error: Job ID file not found." >&2
    return 1
  fi

  execute_qsub() {
    local qsub_output
    local qsub_return
    local job_id

    qsub_output=$(qsub "$@")
    qsub_return=$?
    echo "$qsub_output"

    if [ $qsub_return -eq 0 ]; then
      job_id=$(echo "$qsub_output" | awk 'NR == 1 {print $2}')
      if [[ "$job_id" =~ $JOB_ID_REGEX ]]; then
        echo "$job_id" > "$LAST_JOB_FILE"
      else
        echo "WARNING: The returned job ID ('$job_id') does not match the expected format." \
             " Please check the job ID format and ensure it conforms to the expected pattern: '[0-9]+\.nqsv'." >&2
      fi
      return 0
    else
      echo "Error: Job submission failed." >&2
      return 1
    fi
  }

  if [[ "$LAST_JOB_ID" =~ $JOB_ID_REGEX ]]; then
    if execute_qsub --after "$LAST_JOB_ID" "$@"; then
      return 0
    fi
  fi

  # --after付きqsubが失敗した場合、該当ジョブは既に存在しない。
  # --after無しで再度qsubする
  execute_qsub "$@"
}

time_json() {
    FORMAT=$(cat <<EOF
{
  "Command": "%C",
  "UnsharedDataSize(KB)": %D,
  "ElapsedTime": "%E",
  "MajorPageFaults": %F,
  "FileSystemInputs": %I,
  "TotalMemory(KB)": %K,
  "MaxResidentSetSize(KB)": %M,
  "FileSystemOutputs": %O,
  "CpuUsage": "%P",
  "MinorPageFaults": %R,
  "SystemCpuSeconds": %S,
  "UserCpuSeconds": %U,
  "Swaps": %W,
  "SharedTextSize(KB)": %X,
  "PageSize(Bytes)": %Z,
  "InvoluntaryContextSwitches": %c,
  "ElapsedTime(Seconds)": %e,
  "SignalsDelivered": %k,
  "UnsharedStackSize(KB)": %p,
  "SocketMessagesReceived": %r,
  "SocketMessagesSent": %s,
  "AverageResidentSetSize(KB)": %t,
  "VoluntaryContextSwitches": %w,
  "ExitStatus": %x
}
EOF
)
    /usr/bin/time -f "$FORMAT" "$@"
}

# 2d限定 cartesian gridのプロセス数x yをできるだけ正方形になるように決定する関数
function dims_create_2d() {
    local np=$1
    local i j
    # Find the largest factor of np less than or equal to sqrt(np)
    for ((i=$(echo "sqrt($np)" | bc); i>0; i--)); do
        if ((np % i == 0)); then
            j=$((np / i))
            echo "$i $j"
            return
        fi
    done
}
