# 基于 nvcr.io/nvidia/pytorch:24.07-py3 镜像
FROM nvcr.io/nvidia/pytorch:24.07-py3

# 安装必要的依赖项
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    vim \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /root

# 下载并安装 Anaconda
RUN wget https://repo.anaconda.com/archive/Anaconda3-2024.02-1-Linux-x86_64.sh && \
    bash Anaconda3-2024.02-1-Linux-x86_64.sh -b -p /root/anaconda3 && \
    rm Anaconda3-2024.02-1-Linux-x86_64.sh

# 设置环境变量
ENV PATH="/root/anaconda3/bin:${PATH}"

# 在.bashrc中添加source /root/anaconda3/etc/profile.d/conda.sh
RUN echo "source /root/anaconda3/etc/profile.d/conda.sh" >> /root/.bashrc && \
    echo "conda activate unsloth_env" >> /root/.bashrc

# 创建unsloth_env虚拟环境
RUN /root/anaconda3/bin/conda create -n unsloth_env \
    python=3.11 \
    pytorch-cuda=12.1 \
    pytorch cudatoolkit xformers -c pytorch -c nvidia -c xformers \
    -y

# 激活虚拟环境
SHELL ["/root/anaconda3/bin/conda", "run", "-n", "unsloth_env", "/bin/bash", "-c"]

# 在虚拟环境中安装 unsloth 和 xformers
RUN pip install unsloth==2025.3.19 && \
    pip install -U xformers --index-url https://download.pytorch.org/whl/cu124

# 启动时运行 Bash shell
CMD ["/bin/bash"]