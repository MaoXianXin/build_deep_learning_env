# 使用基础镜像
FROM registry.baidubce.com/paddlepaddle/paddle:2.5.1-gpu-cuda12.0-cudnn8.9-trt8.6

# 安装指定的Python包
RUN pip install paddlehub==2.4.0 \
    && pip install protobuf==3.20.3

# 将本地的requirements.txt复制到容器中的/root目录
COPY requirements.txt /root/requirements.txt

# 安装requirements.txt中的依赖
RUN pip install -r /root/requirements.txt

# 创建/paddle目录
RUN mkdir /paddle

# 从本地复制PaddleOCR仓库到容器的/paddle目录
COPY PaddleOCR /paddle/PaddleOCR

# 复制本地文件到PaddleOCR/inference目录
COPY ch_PP-OCRv4_det_server_infer /paddle/PaddleOCR/inference/ch_PP-OCRv4_det_server_infer
COPY ch_PP-OCRv4_rec_server_infer /paddle/PaddleOCR/inference/ch_PP-OCRv4_rec_server_infer
COPY en_PP-OCRv4_rec_mrz /paddle/PaddleOCR/inference/en_PP-OCRv4_rec_mrz
COPY en_PP-OCRv4_rec_vis /paddle/PaddleOCR/inference/en_PP-OCRv4_rec_vis
COPY en_PP-OCRv4_rec_vis_gray /paddle/PaddleOCR/inference/en_PP-OCRv4_rec_vis_gray

# 设置工作目录
WORKDIR /paddle/PaddleOCR

# 安装指定的Python包
RUN pip install torch==1.11.0+cu113 torchvision==0.12.0+cu113 torchaudio==0.11.0 --extra-index-url https://download.pytorch.org/whl/cu113
RUN pip install pyyaml==6.0 tqdm==4.65.0 opencv-python==4.7.0.72 pandas==2.0.2 matplotlib==3.7.1 seaborn==0.11.2 tensorboard==2.13.0 scipy==1.10.1 pillow==9.5.0 numpy==1.21.4

# 将本地的Arial.ttf复制到容器中的/root/.config/Ultralytics目录
COPY Arial.ttf /root/.config/Ultralytics/Arial.ttf
COPY yolov5 /yolov5

# 安装 supervisor
RUN apt-get update && apt-get install -y supervisor

# 复制 supervisord 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 运行deploy_hubserving.sh脚本和Flask服务
CMD ["/usr/bin/supervisord"]