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

# 从.env文件加载环境变量
if [ -f ".env" ]; then
    source .env
else
    error_exit ".env 文件不存在"
fi

# Print the NODES variable
echo "NODES from .env: $NODES"

# 解析NODES字符串为数组
declare -A NODES_ARRAY
declare -A REPLICAS_ARRAY
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

# Print the NODE_ARRAY
echo "Parsed NODE_ARRAY: ${NODE_ARRAY[@]}"

for node in "${NODE_ARRAY[@]}"; do
    IFS=':' read -r ip gpu_count replicas <<< "$node"
    if [[ -n "$ip" && -n "$gpu_count" && -n "$replicas" ]]; then
        NODES_ARRAY[$ip]=$gpu_count
        REPLICAS_ARRAY[$ip]=$replicas
    else
        error_exit "NODES 格式错误: $node"
    fi
done

# 打印出NODES的值
echo "NODES values:"
for ip in "${!NODES_ARRAY[@]}"; do
    echo "IP: $ip, GPU Count: ${NODES_ARRAY[$ip]}, Replicas: ${REPLICAS_ARRAY[$ip]}"
done

# 解析服务配置
declare -A BASE_PORTS CONTAINER_PORTS API_PATHS
for service in "${SERVICES[@]}"; do
    IFS=':' read -r name base_port container_port api_path <<< "$service"
    BASE_PORTS[$name]=$base_port
    CONTAINER_PORTS[$name]=$container_port
    API_PATHS[$name]=$api_path
done

# 创建Nginx配置
cat > nginx.conf <<EOF
worker_processes auto;  # 自动检测CPU核心数
worker_rlimit_nofile 65535;  # 提高工作进程的最大文件描述符数量

events {
    use epoll;  # 使用epoll事件驱动模型
    worker_connections ${NGINX_WORKER_CONNECTIONS};
    multi_accept on;  # 开启一次接受多个新连接
}

http {
    # 基础配置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;
    types_hash_max_size 2048;
    client_max_body_size 10m;
    client_body_buffer_size 128k;

    # MIME类型设置
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length 1k;

    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # 动态生成upstream配置
$(for service in "${!BASE_PORTS[@]}"; do
    cat <<EOFUPSTREAM
    upstream ocr_${service} {
        least_conn;
        keepalive 32;
$(for ip in "${!NODES_ARRAY[@]}"; do
    for gpu_id in $(seq 0 $((${NODES_ARRAY[$ip]}-1))); do
        gpu_port_offset=$((gpu_id * PORT_OFFSET_PER_GPU))
        for replica_id in $(seq 0 $((${REPLICAS_ARRAY[$ip]}-1))); do
            replica_port_offset=$((replica_id * PORT_OFFSET_PER_REPLICA))
            port=$((BASE_PORTS[$service] + gpu_port_offset + replica_port_offset))
            echo "        server ${ip}:${port} max_fails=3 fail_timeout=30s;"
        done
    done
done)
    }

EOFUPSTREAM
done)

    # 动态生成server配置
$(for service in "${!BASE_PORTS[@]}"; do
    cat <<EOFSERVER
    server {
        listen ${CONTAINER_PORTS[$service]};
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location ${API_PATHS[$service]} {
            proxy_pass http://ocr_${service};
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            proxy_buffer_size 4k;
            proxy_buffers 4 32k;
            proxy_busy_buffers_size 64k;
        }
    }

EOFSERVER
done)
}
EOF

# 添加配置文件检查
echo "检查生成的nginx配置文件..."
cat nginx.conf

# 使用nginx -t检查配置文件语法
docker run --rm \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    ${NGINX_IMAGE} \
    nginx -t || error_exit "Nginx配置文件语法检查失败"

# 检查必要的端口
PORTS=(${CONTAINER_PORT_SYSTEM} ${CONTAINER_PORT_VIS} ${CONTAINER_PORT_MRZ} ${CONTAINER_PORT_GRAY})
for PORT in "${PORTS[@]}"; do
    if ! check_port $PORT; then
        error_exit "端口 $PORT 已被占用"
    fi
done

# 检查必要的文件
if [ ! -f "nginx.conf" ]; then
    error_exit "nginx.conf 配置文件不存在"
fi

# 启动Nginx容器时添加日志挂载
echo "正在启动 Nginx 容器..."
CONTAINER_ID=$(docker run -d \
    --name ${NGINX_CONTAINER_NAME} \
    --network host \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    -v $(pwd)/nginx_logs:/var/log/nginx \
    ${NGINX_IMAGE})

# 添加容器状态检查
if [ ! "$(docker ps -q -f id=${CONTAINER_ID})" ]; then
    echo "Nginx容器启动失败，查看容器日志："
    docker logs ${CONTAINER_ID}
    error_exit "Nginx容器未能正常运行"
fi

echo "Nginx 容器已启动:"
echo "容器 ID: ${CONTAINER_ID:0:12}"
echo "容器名称: ${NGINX_CONTAINER_NAME}"
echo "使用端口: ${PORTS[*]}"
echo "配置文件: $(pwd)/nginx.conf"

echo "负载均衡配置已完成，Nginx正在运行。"

# 取消EXIT trap
trap - EXIT