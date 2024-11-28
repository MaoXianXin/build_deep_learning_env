#!/bin/bash
set -e  # 脚本遇到错误立即退出

# 清理函数
cleanup() {
    echo "正在清理..."
    # 清理nginx容器
    containers=$(docker ps -a | grep 'nginx-ocr' | awk '{print $1}')
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

# 端口检查函数
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 1
    fi
    return 0
}

# 在主逻辑开始前先执行清理
cleanup

# 定义所有节点的IP地址和GPU数量
declare -A NODES
NODES=(
    ["192.168.3.23"]=1  # 节点IP和GPU数量
    ["192.168.1.15"]=1
)

BASE_PORT_SYSTEM=18842
BASE_PORT_VIS=18843
BASE_PORT_MRZ=18844
BASE_PORT_GRAY=18845

# 创建Nginx配置
cat > nginx.conf <<EOF
events {
    worker_connections 1024;
}

http {
    # 定义四种服务的upstream
    upstream ocr_system {
$(for ip in "${!NODES[@]}"; do
    for gpu_id in $(seq 0 $((${NODES[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_SYSTEM + gpu_id * 10));"
    done
done)
    }
    upstream ocr_rec_vis {
$(for ip in "${!NODES[@]}"; do
    for gpu_id in $(seq 0 $((${NODES[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_VIS + gpu_id * 10));"
    done
done)
    }
    upstream ocr_rec_mrz {
$(for ip in "${!NODES[@]}"; do
    for gpu_id in $(seq 0 $((${NODES[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_MRZ + gpu_id * 10));"
    done
done)
    }
    upstream ocr_rec_vis_gray {
$(for ip in "${!NODES[@]}"; do
    for gpu_id in $(seq 0 $((${NODES[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_GRAY + gpu_id * 10));"
    done
done)
    }

    # 定义四个服务的负载均衡规则
    server {
        listen 12342;
        location /predict/ocr_system {
            proxy_pass http://ocr_system;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 12343;
        location /predict/ocr_rec_vis {
            proxy_pass http://ocr_rec_vis;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 12344;
        location /predict/ocr_rec_mrz {
            proxy_pass http://ocr_rec_mrz;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 12345;
        location /predict/ocr_rec_vis_gray {
            proxy_pass http://ocr_rec_vis_gray;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF

# 检查必要的端口
PORTS=(12342 12343 12344 12345)
for PORT in "${PORTS[@]}"; do
    if ! check_port $PORT; then
        error_exit "端口 $PORT 已被占用"
    fi
done

# 检查必要的文件
if [ ! -f "nginx.conf" ]; then
    error_exit "nginx.conf 配置文件不存在"
fi

# 启动Nginx容器
echo "正在启动 Nginx 容器..."
CONTAINER_ID=$(docker run -d \
    --name nginx-ocr \
    --network host \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    nginx:latest)

echo "Nginx 容器已启动:"
echo "容器 ID: ${CONTAINER_ID:0:12}"
echo "容器名称: nginx-ocr"
echo "使用端口: ${PORTS[*]}"
echo "配置文件: $(pwd)/nginx.conf"

echo "负载均衡配置已完成，Nginx正在运行。"

# 取消EXIT trap
trap - EXIT