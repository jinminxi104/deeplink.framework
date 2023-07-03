import os
import sys
import random
from multiprocessing import Pool, Queue, Manager
import subprocess as sp
import time
import yaml


#set some params
max_parall = 4
random_model_num = 4
device_type = sys.argv[1]
github_job = os.environ.get('GITHUB_JOB')
slurm_par = os.environ.get('SLURM_PAR')
gpu_requests = os.environ.get('GPU_REQUESTS')
print("github_job:{},slurm_par:{},gpu_requests:{}".format(github_job,slurm_par,gpu_requests))


print("python path: {}".format(os.environ.get('PYTHONPATH', None)), flush = True)

os.environ['DIPU_DUMP_OP_ARGS'] = "0"


def run_cmd(cmd):
    cp = sp.run(cmd,shell=True, encoding = "utf-8")
    if cp.returncode != 0:
        error = "Some thing wrong has happened when running command [{}]:{}".format(cmd, cp.stderr)
        raise Exception(error)


def process_one_iter(model_info):

    begin_time = time.time()

    model_info_list = model_info.split()
    if(len(model_info_list) < 3 or len(model_info_list) > 4):
        print("wrong model info in  {}".format(model_info), flush = True)
    p1 = model_info_list[0]
    p2 = model_info_list[1]
    p3 = model_info_list[2]
    p4 = model_info_list[3] if len(model_info_list) == 4 else ""

    train_path = p1 + "/tools/train.py"
    config_path = p1 + "/configs/" + p2
    work_dir = "--work-dir=./one_iter_data/" + p3
    opt_arg = p4
    os.environ['ONE_ITER_TOOL_STORAGE_PATH'] = os.getcwd()+"/one_iter_data/" + p3

    print("{} {} {} {}".format(train_path, config_path, work_dir, opt_arg), flush = True)

    if not os.path.exists(os.environ['ONE_ITER_TOOL_STORAGE_PATH']):            
        os.makedirs(os.environ['ONE_ITER_TOOL_STORAGE_PATH']) 

    print("model:{}".format(p2), flush = True)

    github_job_name = github_job+"_"+p2

    cmd1 = "srun --job-name==${} --partition=${}  --gres=${} sh SMART/tools/one_iter_tool/run_one_iter.sh {} {} {} {}".format(github_job_name, slurm_par, gpu_requests, train_path, config_path, work_dir, opt_arg)
    cmd2 = "srun --job-name==${} --partition=${}  --gres=${} sh SMART/tools/one_iter_tool/compare_one_iter.sh".format(github_job_name, slurm_par, gpu_requests)
    run_cmd(cmd1)
    run_cmd(cmd2)

    end_time = time.time()
    run_time = round(end_time - begin_time)
    hour = run_time // 3600
    minute = (run_time - 3600 * hour) // 60
    second = run_time - 3600 * hour - 60 * minute
    print ("The running time of {} :{} hours {} mins {} secs".format(p2, hour, minute, second), flush = True)

    

def handle_error(error):
    print("Error: {}".format(error), flush = True)
    if p is not None:
        print("Kill all!", flush = True)
        p.terminate()
        exit(1)

if __name__=='__main__':
    curPath = os.path.dirname(os.path.realpath(__file__))
    yamlPath = os.path.join(curPath, "test_one_iter_model_list.yaml")
    original_list_f = open(yamlPath, 'r', encoding = 'utf-8')
    original_list_cfg = original_list_f.read()
    original_list_d = yaml.safe_load(original_list_cfg)

    try:
        original_list = original_list_d[device_type]
    except:
        print("The device is not supported!", flush = True)
        exit(1)

    length = len(original_list)

    if(random_model_num > length):
        random_model_num = length  

    print("model num:{}, chosen model num:{}".format(length, random_model_num), flush = True)

    #random choose model
    selected_list = random.sample(original_list, random_model_num)

    os.environ['ONE_ITER_TOOL_DEVICE'] = "dipu"
    os.environ['ONE_ITER_TOOL_DEVICE_COMPARE'] = "cpu"

    os.mkdir("one_iter_data")

    p = None
    try:
        p = Pool(max_parall)
        for i in range(random_model_num):
            p.apply_async(process_one_iter, args = (selected_list[i],), error_callback = handle_error)
        print('Waiting for all subprocesses done...', flush = True)
        p.close()
        p.join()
        print('All subprocesses done.', flush = True)
    except Exception as e:
        print("Error:{}".format(e), flush = True)
        exit(1)
