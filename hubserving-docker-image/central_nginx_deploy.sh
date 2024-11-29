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
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

# Print the NODE_ARRAY
echo "Parsed NODE_ARRAY: ${NODE_ARRAY[@]}"

for node in "${NODE_ARRAY[@]}"; do
    IFS=':' read -r ip gpu_count <<< "$node"
    if [[ -n "$ip" && -n "$gpu_count" ]]; then
        NODES_ARRAY[$ip]=$gpu_count
    else
        error_exit "NODES 格式错误: $node"
    fi
done

# 打印出NODES的值
echo "NODES values:"
for ip in "${!NODES_ARRAY[@]}"; do
    echo "IP: $ip, GPU Count: ${NODES_ARRAY[$ip]}"
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

    # 定义四种服务的upstream
    upstream ocr_system {
        least_conn;  # 最小连接数负载均衡
        keepalive 32;  # 保持后端连接
$(for ip in "${!NODES_ARRAY[@]}"; do
    for gpu_id in $(seq 0 $((${NODES_ARRAY[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_SYSTEM + gpu_id * PORT_OFFSET_PER_GPU)) max_fails=3 fail_timeout=30s;"
    done
done)
    }

    upstream ocr_rec_vis {
        least_conn;
        keepalive 32;
$(for ip in "${!NODES_ARRAY[@]}"; do
    for gpu_id in $(seq 0 $((${NODES_ARRAY[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_VIS + gpu_id * PORT_OFFSET_PER_GPU)) max_fails=3 fail_timeout=30s;"
    done
done)
    }

    upstream ocr_rec_mrz {
        least_conn;
        keepalive 32;
$(for ip in "${!NODES_ARRAY[@]}"; do
    for gpu_id in $(seq 0 $((${NODES_ARRAY[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_MRZ + gpu_id * PORT_OFFSET_PER_GPU)) max_fails=3 fail_timeout=30s;"
    done
done)
    }

    upstream ocr_rec_vis_gray {
        least_conn;
        keepalive 32;
$(for ip in "${!NODES_ARRAY[@]}"; do
    for gpu_id in $(seq 0 $((${NODES_ARRAY[$ip]}-1))); do
        echo "        server $ip:$((BASE_PORT_GRAY + gpu_id * PORT_OFFSET_PER_GPU)) max_fails=3 fail_timeout=30s;"
    done
done)
    }

    # 定义四个服务的负载均衡规则
    server {
        listen ${CONTAINER_PORT_SYSTEM};
        
        # 基础安全头部
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location ${API_PATH_SYSTEM} {
            proxy_pass http://ocr_system;
            
            # 代理设置
            proxy_http_version 1.1;
            proxy_set_header Connection "";  # 开启keepalive
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            
            # 超时设置
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            
            # 缓冲设置
            proxy_buffer_size 4k;
            proxy_buffers 4 32k;
            proxy_busy_buffers_size 64k;
        }
    }

    # 其他三个服务使用相同的配置模式
    server {
        listen ${CONTAINER_PORT_VIS};
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location ${API_PATH_VIS} {
            proxy_pass http://ocr_rec_vis;
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

    server {
        listen ${CONTAINER_PORT_MRZ};
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location ${API_PATH_MRZ} {
            proxy_pass http://ocr_rec_mrz;
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

    server {
        listen ${CONTAINER_PORT_GRAY};
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location ${API_PATH_GRAY} {
            proxy_pass http://ocr_rec_vis_gray;
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
}
EOF

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

# 启动Nginx容器
echo "正在启动 Nginx 容器..."
CONTAINER_ID=$(docker run -d \
    --name ${NGINX_CONTAINER_NAME} \
    --network host \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    ${NGINX_IMAGE})

echo "Nginx 容器已启动:"
echo "容器 ID: ${CONTAINER_ID:0:12}"
echo "容器名称: ${NGINX_CONTAINER_NAME}"
echo "使用端口: ${PORTS[*]}"
echo "配置文件: $(pwd)/nginx.conf"

echo "负载均衡配置已完成，Nginx正在运行。"

# 取消EXIT trap
trap - EXIT