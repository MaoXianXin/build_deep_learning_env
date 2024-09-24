hubserving服务镜像制作参考: hubserving-docker-image.tar压缩包里的Dockerfile文件

启动PaddleOCR服务容器的命令如下:

```
docker run -d --gpus all --shm-size=16g --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 12342:12342 -p 12343:12343 -p 12344:12344 -p 12345:12345 --name hubserving hubserving:v0.2
```

PaddleOCR代码库位置: /paddle/PaddleOCR

在PaddleOCR/tools下存在一个test_hubserving.py脚本，可用于服务是否正常测试:

```
服务名称和端口说明:
ocr_system: 12342
ocr_rec_vis: 12343
ocr_rec_mrz: 12344
ocr_rec_vis_gray: 12345

python tools/test_hubserving.py --server_url=http://127.0.0.1:12342/predict/ocr_system --image_dir=/home/mao/datasets/护照MRZ-OCR优化/all_vis_imgs

python tools/test_hubserving.py --server_url=http://127.0.0.1:12343/predict/ocr_rec_vis --image_dir=/home/mao/workspace/PaddleOCR/test_data/Name_sub_imgs

python tools/test_hubserving.py --server_url=http://127.0.0.1:12345/predict/ocr_rec_vis_gray --image_dir=/home/mao/workspace/PaddleOCR/test_data/Name_sub_imgs

python tools/test_hubserving.py --server_url=http://127.0.0.1:12344/predict/ocr_rec_mrz --image_dir=/home/mao/workspace/PaddleOCR/test_data/fixed_MRZ_sub_imgs
```

一些更多的说明:
ocr_system一些参数说明, PaddleOCR/deploy/hubserving/ocr_system/params.py

```
det_model_dir: 检测模型位置
det_limit_side_len: 推理最长边设置

det_db_thresh: 一般不变就行
det_db_box_thresh: 从默认的0.6设置为0.4，使检测更少漏检
det_db_unclip_ratio: 从默认的1.5设置为2.0，使检测框外扩

rec_model_dir: 识别模型位置

关于参数设置的更多说明可查看该链接: https://paddlepaddle.github.io/PaddleOCR/ppocr/blog/inference_args.html
```
端口设置位置: PaddleOCR/deploy/hubserving/ocr_system/config.json
更改服务名称需同步修改module.py代码中的一些地方: PaddleOCR/deploy/hubserving/ocr_system/module.py:

```
from deploy.hubserving.ocr_system.params import read_params   # 此处ocr_system需要更服务名称同名


@moduleinfo(
    name="ocr_system",  # 此处ocr_system需要更服务名称同名
    version="1.0.0",
    summary="ocr system service",
    author="paddle-dev",
    author_email="paddle-dev@baidu.com",
    type="cv/PP-OCR_system")
```
其它的ocr_rec_vis、ocr_rec_mrz、ocr_rec_vis_gray同理