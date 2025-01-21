# 使用基础镜像
FROM corex:4.0.1-ubuntu

# 安装指定的Python包
RUN pip install paddlehub==2.4.0 \
    && pip install protobuf==3.20.3

RUN apt-get update && apt-get install -y libgl1-mesa-glx libglib2.0-0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 将本地的requirements.txt复制到容器中的/root目录
COPY requirements.txt /root/requirements.txt

# 安装requirements.txt中的依赖
RUN pip install -r /root/requirements.txt

# 安装指定的Python包
RUN pip install seaborn==0.13.2

# 将本地的Arial.ttf复制到容器中的/root/.config/Ultralytics目录
COPY Arial.ttf /root/.config/Ultralytics/Arial.ttf

# 安装 supervisor
RUN apt-get update && apt-get install -y supervisor

# 复制 supervisord 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 运行deploy_hubserving.sh脚本和Flask服务
CMD ["/usr/bin/supervisord"]