#!/bin/bash

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

# 启动Nginx容器
docker rm -f nginx-lb 2>/dev/null
docker run -d \
    --name nginx-lb \
    --network host \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    nginx:latest

echo "负载均衡配置已完成，Nginx正在运行。"
