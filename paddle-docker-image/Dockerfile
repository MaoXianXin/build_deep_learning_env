# 使用基础镜像
FROM registry.baidubce.com/paddlepaddle/paddle:2.5.1-gpu-cuda12.0-cudnn8.9-trt8.6

# 安装指定的Python包
RUN pip install scikit-image imgaug pyclipper albumentations lmdb tqdm rapidfuzz visualdl numpy==1.26.2 -i https://pypi.tuna.tsinghua.edu.cn/simple some-package


CMD ["/bin/bash"]