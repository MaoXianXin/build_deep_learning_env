# 使用基础镜像
FROM registry.baidubce.com/paddlepaddle/paddle:2.5.1-gpu-cuda12.0-cudnn8.9-trt8.6

# 安装指定的Python包
RUN pip install paddlehub==2.4.0 \
    && pip install protobuf==3.20.3

# 将本地的requirements.txt复制到容器中的/root目录
COPY requirements.txt /root/requirements.txt

# 安装requirements.txt中的依赖
RUN pip install -r /root/requirements.txt

# 启动时运行 Bash shell
CMD ["/bin/bash"]