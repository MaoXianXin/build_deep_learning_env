# 基于 Ubuntu 18.04 镜像
FROM supermicro.gpus.tecrun.com:5000/tecrun/ubuntu18.04:cuda11.2-cudnn8.1-dev1.0

# 安装必要的依赖项
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    vim \
    && rm -rf /var/lib/apt/lists/*

# 下载并安装 Anaconda
RUN wget https://repo.anaconda.com/archive/Anaconda3-2024.02-1-Linux-x86_64.sh && \
    bash Anaconda3-2024.02-1-Linux-x86_64.sh -b -p /opt/anaconda3 && \
    rm Anaconda3-2024.02-1-Linux-x86_64.sh

# 设置环境变量
ENV PATH="/opt/anaconda3/bin:${PATH}"

# 在.bashrc中添加source /opt/anaconda3/etc/profile.d/conda.sh
RUN echo "source /opt/anaconda3/etc/profile.d/conda.sh" >> /root/.bashrc && \
    echo "conda activate yolov5" >> /root/.bashrc

# 创建虚拟环境
RUN conda create -n yolov5 python=3.10

# 激活虚拟环境
SHELL ["conda", "run", "-n", "yolov5", "/bin/bash", "-c"]

# 在虚拟环境中安装 PyTorch
RUN conda install -y pytorch==1.11.0 torchvision==0.12.0 torchaudio==0.11.0 cudatoolkit=11.3 -c pytorch && pip install pyyaml==6.0 tqdm==4.65.0 opencv-python==4.7.0.72 pandas==2.0.2 matplotlib==3.7.1 seaborn==0.11.2 tensorboard==2.13.0 scipy==1.10.1 pillow==9.5.0 numpy==1.21.4

# 安装额外的依赖项
RUN apt-get update && \
    apt-get install -y libgl1-mesa-dev libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# 下载Arial.ttf字体文件
RUN mkdir -p /root/.config/Ultralytics && \
    wget -O /root/.config/Ultralytics/Arial.ttf https://ultralytics.com/assets/Arial.ttf

# 启动时运行 Bash shell
CMD ["/bin/bash"]