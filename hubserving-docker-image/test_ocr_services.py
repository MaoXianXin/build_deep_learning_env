import requests
import os
import time
import argparse
from concurrent.futures import ThreadPoolExecutor
import logging
from dotenv import load_dotenv
import base64

"""
测试直接服务端点:
python test_ocr_services.py \
    --test_dirs /home/mao/datasets/LLM结构化提取/LLM训练数据/USA-134 \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_Name_sub_imgs \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_MRZ_sub_imgs \
    --services system vis mrz

测试Nginx负载均衡端点:
python test_ocr_services.py \
    --test_dirs /home/mao/datasets/LLM结构化提取/LLM训练数据/USA-134 \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_Name_sub_imgs \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_MRZ_sub_imgs \
    --services system vis mrz \
    --nginx
"""

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class OCRServiceTester:
    def __init__(self):
        # Load environment variables from .env
        load_dotenv()
        
        # Direct service ports
        self.base_ports = {
            'system': int(os.getenv('BASE_PORT_SYSTEM')),
            'vis': int(os.getenv('BASE_PORT_VIS')),
            'mrz': int(os.getenv('BASE_PORT_MRZ')),
            'gray': int(os.getenv('BASE_PORT_GRAY'))
        }
        
        # Nginx load balancer ports
        self.container_ports = {
            'system': int(os.getenv('CONTAINER_PORT_SYSTEM')),
            'vis': int(os.getenv('CONTAINER_PORT_VIS')),
            'mrz': int(os.getenv('CONTAINER_PORT_MRZ')),
            'gray': int(os.getenv('CONTAINER_PORT_GRAY'))
        }
        
        # API paths
        self.api_paths = {
            'system': os.getenv('API_PATH_SYSTEM'),
            'vis': os.getenv('API_PATH_VIS'),
            'mrz': os.getenv('API_PATH_MRZ'),
            'gray': os.getenv('API_PATH_GRAY')
        }

    def test_endpoint(self, url, image_path):
        """Test a single endpoint with an image."""
        try:
            # 读取图片并转换为base64
            with open(image_path, 'rb') as f:
                image_bytes = f.read()
            
            image_base64 = base64.b64encode(image_bytes).decode('utf-8')
            
            # 构建JSON请求数据
            json_data = {
                "images": [image_base64]
            }
            
            # 发送JSON格式的POST请求
            headers = {'Content-Type': 'application/json'}
            response = requests.post(url, json=json_data, headers=headers)
            
            if response.status_code == 200:
                result = response.json()
                return True, result
            else:
                return False, f"HTTP {response.status_code}: {response.text}"
                
        except Exception as e:
            return False, str(e)

    def test_service(self, service_type, image_dir, use_nginx=False):
        """Test a specific service with all images in the directory."""
        port = self.container_ports[service_type] if use_nginx else self.base_ports[service_type]
        base_url = f"http://127.0.0.1:{port}{self.api_paths[service_type]}"
        
        logger.info(f"Testing {service_type} service at {base_url}")
        logger.info(f"Using {'Nginx load balancer' if use_nginx else 'direct service'}")

        success_count = 0
        total_count = 0
        
        for image_name in os.listdir(image_dir):
            if image_name.lower().endswith(('.png', '.jpg', '.jpeg')):
                total_count += 1
                image_path = os.path.join(image_dir, image_name)
                success, result = self.test_endpoint(base_url, image_path)
                
                if success:
                    success_count += 1
                    logger.debug(f"Successfully processed {image_name}")
                else:
                    logger.error(f"Failed to process {image_name}: {result}")

        return success_count, total_count

def main():
    parser = argparse.ArgumentParser(description='Test OCR services')
    parser.add_argument('--test_dirs', type=str, required=True, nargs='+',
                       help='Directories containing test images (space-separated)')
    parser.add_argument('--services', type=str, nargs='+',
                       default=['system', 'vis', 'mrz'],
                       help='Services to test (space-separated)')
    parser.add_argument('--nginx', action='store_true',
                       help='Test Nginx load balanced endpoints')
    args = parser.parse_args()

    tester = OCRServiceTester()
    
    # Validate directories and services
    if len(args.test_dirs) != len(args.services):
        logger.error(f"Number of test directories ({len(args.test_dirs)}) must match number of services ({len(args.services)})")
        return

    for test_dir in args.test_dirs:
        if not os.path.exists(test_dir):
            logger.error(f"Directory not found: {test_dir}")
            return

    # Run tests for each service-directory pair
    for service, test_dir in zip(args.services, args.test_dirs):
        if service not in tester.base_ports:
            logger.error(f"Unknown service: {service}")
            continue
            
        logger.info(f"\nTesting {service} service with images from {test_dir}")
        success_count, total_count = tester.test_service(
            service, test_dir, use_nginx=args.nginx
        )
        
        logger.info(
            f"Results for {service}:\n"
            f"Success rate: {success_count}/{total_count} "
            f"({success_count/total_count*100:.2f}%)"
        )

if __name__ == "__main__":
    main()