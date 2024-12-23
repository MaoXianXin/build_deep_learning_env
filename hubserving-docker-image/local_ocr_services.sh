#!/bin/bash
set -e  # 脚本遇到错误立即退出

# 从.env文件加载环境变量
if [ -f ".env" ]; then
    source .env
else
    error_exit ".env 文件不存在"
fi

# 清理函数
cleanup() {
    echo "正在清理..."
    containers=$(docker ps -a | grep "${CONTAINER_PREFIX}" | awk '{print $1}')
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

# 解析服务配置
declare -A BASE_PORTS CONTAINER_PORTS API_PATHS
for service in "${SERVICES[@]}"; do
    IFS=':' read -r name base_port container_port api_path <<< "$service"
    BASE_PORTS[$name]=$base_port
    CONTAINER_PORTS[$name]=$container_port
    API_PATHS[$name]=$api_path
done

# 检查端口
for gpu_id in $(seq 0 $(($NUM_GPUS-1))); do
    port_offset=$((gpu_id * PORT_OFFSET_PER_GPU))
    for service in "${!BASE_PORTS[@]}"; do
        port=$((BASE_PORTS[$service] + port_offset))
        if ! check_port $port; then
            error_exit "端口 $port 已被占用"
        fi
    done
done

# 启动容器
for gpu_id in $(seq 0 $(($NUM_GPUS-1))); do
    port_offset=$((gpu_id * PORT_OFFSET_PER_GPU))
    port_mappings=""
    for service in "${!BASE_PORTS[@]}"; do
        port_mappings+=" -p $((BASE_PORTS[$service] + port_offset)):${CONTAINER_PORTS[$service]}"
    done
    
    container_id=$(docker run -d \
        --gpus "device=$gpu_id" \
        --shm-size=${DOCKER_SHM_SIZE} \
        --ipc=${DOCKER_IPC} \
        $port_mappings \
        -e CUDA_VISIBLE_DEVICES=0 \
        -v "$(pwd)/PaddleOCR:/paddle/PaddleOCR" \
        -v "$(pwd)/ch_PP-OCRv4_det_server_infer:/paddle/PaddleOCR/inference/ch_PP-OCRv4_det_server_infer" \
        -v "$(pwd)/ch_PP-OCRv4_rec_server_infer:/paddle/PaddleOCR/inference/ch_PP-OCRv4_rec_server_infer" \
        -v "$(pwd)/en_PP-OCRv4_rec_mrz:/paddle/PaddleOCR/inference/en_PP-OCRv4_rec_mrz" \
        -v "$(pwd)/en_PP-OCRv4_rec_vis:/paddle/PaddleOCR/inference/en_PP-OCRv4_rec_vis" \
        -v "$(pwd)/en_PP-OCRv4_rec_vis_gray:/paddle/PaddleOCR/inference/en_PP-OCRv4_rec_vis_gray" \
        --name ${CONTAINER_PREFIX}$gpu_id \
        ${DOCKER_IMAGE})
    echo "GPU $gpu_id 的服务容器已启动，容器ID: ${container_id:0:12}"
done

echo "本机OCR服务已启动，每个容器暴露以下端口："
for service in "${!BASE_PORTS[@]}"; do
    echo "$service 起始端口: ${BASE_PORTS[$service]}"
done

# 取消EXIT trap
trap - EXIT
