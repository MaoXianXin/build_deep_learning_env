#!/bin/bash
set -e  # 脚本遇到错误立即退出

# 清理函数
cleanup() {
    echo "正在清理..."
    containers=$(docker ps -a | grep 'hubserving_' | awk '{print $1}')
    if [ ! -z "$containers" ]; then
        docker rm -f $containers || true
    fi
}

# 注册中断处理
trap cleanup EXIT SIGINT SIGTERM

# 错误处理函数
error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 添加端口检查函数
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 1
    fi
    return 0
}

# 在主逻辑开始前先执行清理
cleanup

# 定义本机的GPU数量和基础端口
if ! command -v nvidia-smi &> /dev/null; then
    echo "错误: nvidia-smi 命令不可用，请确保NVIDIA驱动已正确安装"
    exit 1
fi

NUM_GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
if [ $NUM_GPUS -eq 0 ]; then
    echo "错误: 未检测到可用的GPU"
    exit 1
fi

BASE_PORT_SYSTEM=18842  # OCR System服务起始端口
BASE_PORT_VIS=18843      # OCR Rec Vis服务起始端口
BASE_PORT_MRZ=18844      # OCR Rec MRZ服务起始端口
BASE_PORT_GRAY=18845     # OCR Rec Vis Gray服务起始端口

# 在启动容器前检查端口
for gpu_id in $(seq 0 $(($NUM_GPUS-1))); do
    port_offset=$((gpu_id * 10))
    for port in $((BASE_PORT_SYSTEM + port_offset)) $((BASE_PORT_VIS + port_offset)) $((BASE_PORT_MRZ + port_offset)) $((BASE_PORT_GRAY + port_offset)); do
        if ! check_port $port; then
            echo "错误: 端口 $port 已被占用"
            exit 1
        fi
    done
done

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

# 取消EXIT trap
trap - EXIT
