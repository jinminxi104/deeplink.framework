#!/bin/bash

export DIPU_DUMP_OP_ARGS=1

pip install pyquaternion
pip install trimesh

#创建一个二维的列表，分别为train文件位置，配置文件位置，workdir位置和可选参数
original_list=(
    # # mmpretrain
    # "mmpretrain resnet/resnet50_8xb32_in1k.py workdirs_resnet50_8xb32_in1k"   
    # "mmpretrain swin_transformer/swin-large_16xb64_in1k.py workdirs_swin-large_16xb64_in1k"   
    # "mmpretrain vision_transformer/vit-base-p16_64xb64_in1k-384px.py workdirs_vit-base-p16_64xb64_in1k-384px"
    # "mmpretrain efficientnet/efficientnet-b2_8xb32_in1k.py workdirs_efficientnet-b2_8xb32_in1k"  
    # "mmpretrain mobilenet_v3/mobilenet-v3-large_8xb128_in1k.py workdirs_mobilenet-v3-large_8xb128_in1k" 
    # # mmdetection
    # "mmdetection detr/detr_r50_8xb2-150e_coco.py workdirs_detr_r50_8xb2-150e_coco"  
    # "mmdetection yolo/yolov3_d53_8xb8-320-273e_coco.py workdirs_yolov3_d53_8xb8-320-273e_coco" 
    # "mmdetection ssd/ssd300_coco.py workdirs_ssd300_coco" 
    # "mmdetection fcos/fcos_r50-dcn-caffe_fpn_gn-head-center-normbbox-centeronreg-giou_1x_coco.py workdirs_fcos_r50-dcn-caffe_fpn_gn-head-center-normbbox-centeronreg-giou_1x_coco" 
    # "mmdetection retinanet/retinanet_r50_fpn_1x_coco.py workdirs_retinanet_r50_fpn_1x_coco"  
    ## mmpose
    # "mmpose body_2d_keypoint/topdown_heatmap/coco/td-hm_hrnet-w32_udp-8xb64-210e_coco-256x192.py workdirs_td-hm_hrnet-w32_udp-8xb64-210e_coco-256x192" 
    ## mmaction2
    # "mmaction2 recognition/tsn/tsn_imagenet-pretrained-r50_8xb32-1x1x3-100e_kinetics400-rgb.py workdirs_tsn_imagenet-pretrained-r50_8xb32-1x1x3-100e_kinetics400-rgb" 
    # mmocr    
    "mmocr textrecog/crnn/crnn_mini-vgg_5e_mj.py workdirs_crnn_mini-vgg_5e_mj"
    # # mmsegmentation
    # "mmsegmentation deeplabv3/deeplabv3_r50-d8_4xb2-40k_cityscapes-512x1024.py workdirs_r50-d8_4xb2-40k_cityscapes-512x1024" 
    # "mmsegmentation deeplabv3plus/deeplabv3plus_r50-d8_4xb2-40k_cityscapes-512x1024.py workdirs_deeplabv3plus_r50-d8_4xb2-40k_cityscapes-512x1024"
    # 超时
    "mmpretrain convnext/convnext-small_32xb128_in1k.py workdirs_convnext-small_32xb128_in1k" #时间过长
    "mmsegmentation unet/unet-s5-d16_fcn_4xb4-160k_cityscapes-512x1024.py workdirs_unet-s5-d16_fcn_4xb4-160k_cityscapes-512x1024" #时间过长
    "mmsegmentation pspnet/pspnet_r50-d8_4xb2-40k_cityscapes-512x1024.py workdirs_pspnet_r50-d8_4xb2-40k_cityscapes-512x1024"  #时间过长
    # "mmdetection faster_rcnn/faster-rcnn_r101_fpn_1x_coco.py workdirs_faster-rcnn_r101_fpn_1x_coco"
    # "mmagic configs/stable_diffusion/stable-diffusion_ddim_denoisingunet_infer.py workdirs_stable-diffusion_ddim_denoisingunet.py" 
    "mmdetection mask_rcnn/mask-rcnn_r50_fpn_1x_coco.py workdirs_mask-rcnn_r50_fpn_1x_coco"
    "mmdetection3d pointpillars/pointpillars_hv_secfpn_8xb6-160e_kitti-3d-3class.py workdirs_pointpillars_hv_secfpn_8xb6-160e_kitti-3d-3class"
)


length=${#original_list[@]}
max_parall=8
random_model_num=40 #如果超过，会自动设置为模型总数

if [ $random_model_num -gt $length ]; then
    random_model_num=$length
fi

echo "modelnum: $length  chosen model num: $random_model_num"
selected_list=()

# 随机选取模型
for ((i=0; i<random_model_num; i++)); do
    random_index=$((RANDOM % length))
    random_element=${original_list[random_index]}
    selected_list+=("$random_element")
    original_list=("${original_list[@]:0:random_index}" "${original_list[@]:random_index+1}")
    length=${#original_list[@]}
done

job_name=$1
partition=${@:3}
gpu_request=$2

mkfifo ./fifo.$$ && exec 796<> ./fifo.$$ && rm -f ./fifo.$$
for ((i=0; i<$max_parall; i++)); do
    echo  "init add placed row $i" >&796
done

pids=()

export ONE_ITER_TOOL_DEVICE=dipu
export ONE_ITER_TOOL_DEVICE_COMPARE=cpu


mkdir one_iter_data

for ((i=0; i<$random_model_num; i++)); do
{
    set -e

    # 记录开始时间（以纳秒为单位）
    startTime=$(date +%s%N)

    pid=$BASHPID  # 存储子进程的PID号
    read -u 796
    echo "===========", ${selected_list[i]}
    read -r p1 p2 p3 p4 <<< ${selected_list[i]}
    train_path="${p1}/tools/train.py"
    config_path="${p1}/configs/${p2}"
    work_dir="--work-dir=./one_iter_data/${p3}"
    opt_arg="${p4}"
    export ONE_ITER_TOOL_STORAGE_PATH=$(pwd)/one_iter_data/${p3}
    echo "${train_path} ${config_path} ${work_dir} ${opt_arg}"
    if [ -d "$ONE_ITER_TOOL_STORAGE_PATH" ]; then
        echo "File already exists $ONE_ITER_TOOL_STORAGE_PATH"
    else
        # 创建当前文件夹路径
        mkdir -p "$ONE_ITER_TOOL_STORAGE_PATH"
        echo "make dir"
    fi
    srun --job-name=${job_name} -p ${partition} --gres=gpu:${gpu_request} sh SMART/tools/one_iter_tool/run_one_iter.sh ${train_path} ${config_path} ${work_dir} ${opt_arg}
    srun --job-name=${job_name} -p ${partition} --gres=gpu:${gpu_request} sh SMART/tools/one_iter_tool/compare_one_iter.sh
    echo  "after add place row $i"  1>&796
    touch "$pid.done"

    # 记录结束时间（以纳秒为单位）
    endTime=$(date +%s%N)

    # 计算时间差（以纳秒为单位）
    timeDiff=$((endTime - startTime))

    # 将时间差转换为小时、分钟和秒
    seconds=$((timeDiff / 1000000000))
    minutes=$((seconds / 60))
    seconds=$((seconds % 60))
    hours=$((minutes / 60))
    minutes=$((minutes % 60))

    # 显示结果
    echo "The running time of ${p2} ：${hours} H ${minutes} min ${seconds} min"

}&
pid=$!  # 存储子进程的PID号
pids+=("$pid")
read -r p1 p2 p3 p4 <<< ${selected_list[i]}
echo "PID: $pid ,name:$p2"  # 输出子进程的PID号
done

# while true; do
#     all_finished=true
#     for index in "${!pids[@]}"; do
#         pid="${pids[index]}"
#         if ! kill -0 "$pid" 2>/dev/null; then
#             # 如果存在 "$pid.done"，那直接删
#             if [ -f "$pid.done" ]; then
#                 echo "Child process with PID $pid exited successfully."
#                 rm -rf "$pid.done"
#                 unset 'pids[index]'  # 删除相应的数组元素
#                 continue
#             fi
#             echo "Child process with PID $pid encountered an error. Exiting all child processes."
#             # 结束所有子进程
#             for pid_to_kill in "${pids[@]}"; do
#                 kill "$pid_to_kill" 2>/dev/null
#             done
#             exit 1
#         fi
#         all_finished=false
#     done

#     if $all_finished; then
#         break
#     fi

#     sleep 2  # 适当调整轮询的间隔时间
# done
wait


echo Done
