from pathlib import Path
import shutil
import re
import json

BASE_DIR = Path("../raw/ior-pmembb")

target_dirs=[
    "2024.01.23-15.20.41-default",
    "2024.01.23-15.22.18-default",
]

runtypes = ["w", "r", "r_l"]

re_file_time = re.compile(r"([0-9]+)_(r|w|r_l)\.json")
re_file_stderr = re.compile(r"ior_(r|w|r_l)_stderr_([0-9]+)\.txt")
re_file_stdout = re.compile(r"ior_(r|w|r_l)_stdout_([0-9]+)\.txt")
re_file_summary = re.compile(r"ior_summary_(r|w|r_l)_([0-9]+)\.json")
re_file_job_params = re.compile(r"job_params_([0-9]+)\.json")
# re_file_job_params = re.compile(r"jp_([0-9]+)\.json")

def calc_new_runid(runid, runtype):
    for i, rt in enumerate(["w", "r", "r_l"]):
        if runtype == rt:
            return (int(runid) - 1) * 3 + i

for target_dir in target_dirs:
    target_dir = BASE_DIR / target_dir
    job_dirs = [d for d in target_dir.iterdir() if d.is_dir()]
    for job_dir in job_dirs:
        files = [f for f in job_dir.iterdir() if f.is_file()]
        for file in files:
            # m = re_file_time.match(str(file.name))
            # if m:
            #     runid, runtype = m.groups()
            #     file.rename(job_dir / f"time_{calc_new_runid(runid, runtype)}.json")
            # m = re_file_stderr.match(str(file.name))
            # if m:
            #     runtype, runid = m.groups()
            #     file.rename(job_dir / f"ior_stderr_{calc_new_runid(runid, runtype)}.txt")
            # m = re_file_stdout.match(str(file.name))
            # if m:
            #     runtype, runid = m.groups()
            #     file.rename(job_dir / f"ior_stdout_{calc_new_runid(runid, runtype)}.txt")
            # m = re_file_summary.match(str(file.name))
            # if m:
            #     runtype, runid = m.groups()
            #     file.rename(job_dir / f"ior_summary_{calc_new_runid(runid, runtype)}.json")
            # m = re_file_job_params.match(str(file.name))
            # if m:
                # runid, = m.groups()
                # print(file)
                # data = json.loads(file.read_text())
                # print(data)
                # data["runid"] = int(runid)
                # print(json.dumps(data))
                # file.write_text(json.dumps(data))
                # print(json.loads(file.read_text()))
                # start = (int(runid) - 1) * 3
                # file.rename(job_dir / f"jp_{runid}.json")
                # for new_runid in range(start, start+3):
                #     src = str(file)
                #     dst = job_dir / f"job_params_{new_runid}.json"
                #     # print(src, str(dst))
                #     shutil.copy2(file, job_dir / f"job_params_{new_runid}.json")
                # file.unlink()
