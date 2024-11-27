#!/bin/bash

# 定义本机的GPU数量和基础端口
NUM_GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)  # 自动检测GPU数量
BASE_PORT_SYSTEM=18842  # OCR System服务起始端口
BASE_PORT_VIS=18843      # OCR Rec Vis服务起始端口
BASE_PORT_MRZ=18844      # OCR Rec MRZ服务起始端口
BASE_PORT_GRAY=18845     # OCR Rec Vis Gray服务起始端口

# 停止并删除本机的容器
docker rm -f $(docker ps -a | grep 'hubserving_' | awk '{print $1}') 2>/dev/null

# 启动OCR服务容器
for gpu_id in $(seq 0 $(($NUM_GPUS-1))); do
    port_offset=$((gpu_id * 10))  # 每张GPU的端口偏移
    docker run -d \
        --gpus "device=$gpu_id" \
        --shm-size=4g \
        --ipc=host \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        -e CUDA_VISIBLE_DEVICES=$gpu_id \
        -p $((BASE_PORT_SYSTEM + port_offset)):12342 \
        -p $((BASE_PORT_VIS + port_offset)):12343 \
        -p $((BASE_PORT_MRZ + port_offset)):12344 \
        -p $((BASE_PORT_GRAY + port_offset)):12345 \
        --name hubserving_$gpu_id \
        hubserving:v0.1
done

echo "本机OCR服务已启动，每个容器暴露以下端口："
echo "OCR System 起始端口: $BASE_PORT_SYSTEM"
echo "OCR Rec Vis 起始端口: $BASE_PORT_VIS"
echo "OCR Rec MRZ 起始端口: $BASE_PORT_MRZ"
echo "OCR Rec Vis Gray 起始端口: $BASE_PORT_GRAY"
