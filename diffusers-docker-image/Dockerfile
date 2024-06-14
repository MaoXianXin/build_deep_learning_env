# 基于 Ubuntu 18.04 镜像
FROM supermicro.gpus.tecrun.com:5000/tecrun/ubuntu18.04:cuda11.2-cudnn8.1-dev1.0

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
    echo "conda activate llm" >> /root/.bashrc

# 创建虚拟环境
RUN /root/anaconda3/bin/conda create -n llm python=3.10

# 激活虚拟环境
SHELL ["/root/anaconda3/bin/conda", "run", "-n", "llm", "/bin/bash", "-c"]

# 在虚拟环境中安装 PyTorch
RUN conda install -y pytorch==2.2.1 torchvision==0.17.1 torchaudio==2.2.1 pytorch-cuda=12.1 -c pytorch -c nvidia

# 在虚拟环境中安装 python包
RUN pip install pydantic==2.7.0 datasets==2.19.0 transformers==4.40.0 peft==0.10.0 trl==0.8.5 gradio==4.27.0 vllm==0.4.1 jieba==0.42.1 nltk==3.8.1 rouge-chinese==1.0.3

# 复制 diffusers 文件夹到容器中
COPY diffusers /root/diffusers

# 进入 diffusers 文件夹并执行命令
RUN cd /root/diffusers && pip install . && \
    cd examples/text_to_image && pip install -r requirements.txt && \
    accelerate config default

# 复制 install.sh 脚本到容器中
COPY install.sh /root/install.sh

# 执行 install.sh 脚本
RUN bash /root/install.sh

# 启动时运行 Bash shell
CMD ["/bin/bash"]
