#!/bin/bash

# 定义GPU数量和基础端口
NUM_GPUS=1  # 假设有1张GPU卡
BASE_PORT_SYSTEM=18842
BASE_PORT_VIS=18843
BASE_PORT_MRZ=18844
BASE_PORT_GRAY=18845

# 停止并删除已存在的容器
docker rm -f $(docker ps -a | grep 'hubserving_' | awk '{print $1}') 2>/dev/null
docker rm -f nginx-lb 2>/dev/null

# 为每个GPU启动一个容器
for gpu_id in $(seq 0 $(($NUM_GPUS-1))); do
    # 计算端口偏移
    port_offset=$((gpu_id * 10))
    
    # 启动容器
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

# 创建Nginx配置
cat > nginx.conf <<EOF
events {
    worker_connections 1024;
}

http {
    upstream ocr_system {
$(for i in $(seq 0 $(($NUM_GPUS-1))); do echo "        server localhost:$((BASE_PORT_SYSTEM + i * 10));"; done)
    }
    
    upstream ocr_rec_vis {
$(for i in $(seq 0 $(($NUM_GPUS-1))); do echo "        server localhost:$((BASE_PORT_VIS + i * 10));"; done)
    }
    
    upstream ocr_rec_mrz {
$(for i in $(seq 0 $(($NUM_GPUS-1))); do echo "        server localhost:$((BASE_PORT_MRZ + i * 10));"; done)
    }
    
    upstream ocr_rec_vis_gray {
$(for i in $(seq 0 $(($NUM_GPUS-1))); do echo "        server localhost:$((BASE_PORT_GRAY + i * 10));"; done)
    }

    server {
        listen 12342;
        location /predict/ocr_system {
            proxy_pass http://ocr_system/predict/ocr_system;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 12343;
        location /predict/ocr_rec_vis {
            proxy_pass http://ocr_rec_vis/predict/ocr_rec_vis;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 12344;
        location /predict/ocr_rec_mrz {
            proxy_pass http://ocr_rec_mrz/predict/ocr_rec_mrz;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 12345;
        location /predict/ocr_rec_vis_gray {
            proxy_pass http://ocr_rec_vis_gray/predict/ocr_rec_vis_gray;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF

# 启动Nginx容器
docker run -d \
    --name nginx-lb \
    --network host \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    nginx:latest

# 等待服务启动并检查状态
echo "正在等待服务启动..."
sleep 5  # 给容器一些启动时间

# 检查hubserving容器状态
for gpu_id in $(seq 0 $(($NUM_GPUS-1))); do
    if ! docker ps | grep -q "hubserving_$gpu_id"; then
        echo "错误: hubserving_$gpu_id 容器未能正常启动"
        echo "查看容器日志:"
        docker logs hubserving_$gpu_id
        exit 1
    fi
done

# 检查nginx容器状态
if ! docker ps | grep -q "nginx-lb"; then
    echo "错误: nginx-lb 容器未能正常启动"
    echo "查看容器日志:"
    docker logs nginx-lb
    exit 1
fi

echo "所有服务已成功启动!"
echo "服务访问地址："
echo "OCR System: http://127.0.0.1:12342/predict/ocr_system"
echo "OCR Rec Vis: http://127.0.0.1:12343/predict/ocr_rec_vis"
echo "OCR Rec MRZ: http://127.0.0.1:12344/predict/ocr_rec_mrz"
echo "OCR Rec Vis Gray: http://127.0.0.1:12345/predict/ocr_rec_vis_gray"