# 使用基础镜像
FROM nvcr.io/nvidia/pytorch:23.03-py3-v2

# 安装指定的Python包
RUN pip install flask==3.0.3 onnx==1.13.0 onnxruntime==1.19.2

COPY yolov5 /yolov5

# 安装 supervisor
RUN apt-get update && apt-get install -y supervisor

# 复制 supervisord 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 运行deploy_hubserving.sh脚本和Flask服务
CMD ["/usr/bin/supervisord"]