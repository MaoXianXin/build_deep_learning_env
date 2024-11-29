import requests
import os
import time
import argparse
from concurrent.futures import ThreadPoolExecutor
import logging
from dotenv import load_dotenv
import base64
from statistics import mean, median, stdev
from typing import List, Tuple, Dict
import matplotlib.pyplot as plt
import pandas as pd
import threading
from queue import Queue, Empty

"""
测试直接服务端点:
python test_ocr_services.py \
    --test_dirs /home/mao/datasets/LLM结构化提取/LLM训练数据/USA-134 \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_Name_sub_imgs \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_MRZ_sub_imgs \
    --services system vis mrz \
    --thread-analysis

测试Nginx负载均衡端点:
python test_ocr_services.py \
    --test_dirs /home/mao/datasets/LLM结构化提取/LLM训练数据/USA-134 \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_Name_sub_imgs \
                /home/mao/workspace/PaddleOCR/passport_data/fixed_MRZ_sub_imgs \
    --services system vis mrz \
    --nginx \
    --thread-analysis
"""

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class ImagePreloader:
    def __init__(self, max_size=10):
        """初始化预加载器
        Args:
            max_size: 预加载队列的最大大小
        """
        self.queue = Queue(maxsize=max_size)
        self._stop_event = threading.Event()
        self._preload_thread = None

    def start_preloading(self, image_paths: List[str]):
        """启动预加载线程
        Args:
            image_paths: 需要预加载的图片路径列表
        """
        self._stop_event.clear()
        self._preload_thread = threading.Thread(
            target=self._preload_worker,
            args=(image_paths,),
            daemon=True
        )
        self._preload_thread.start()

    def _preload_worker(self, image_paths: List[str]):
        """预加载工作线程"""
        while not self._stop_event.is_set():
            for path in image_paths:
                if self._stop_event.is_set():
                    break
                if not self.queue.full():
                    try:
                        with open(path, 'rb') as f:
                            image_bytes = f.read()
                        image_base64 = base64.b64encode(image_bytes).decode('utf-8')
                        self.queue.put((path, image_base64), timeout=1)
                    except Exception as e:
                        logger.error(f"Error preloading image {path}: {e}")

    def get_next_image(self, timeout=5) -> Tuple[str, str]:
        """获取下一个预加载的图片
        Returns:
            Tuple[str, str]: (图片路径, base64编码的图片数据)
        """
        try:
            return self.queue.get(timeout=timeout)
        except Empty:
            raise TimeoutError("预加载队列为空")

    def stop(self):
        """停止预加载"""
        self._stop_event.set()
        if self._preload_thread and self._preload_thread.is_alive():
            self._preload_thread.join(timeout=1)

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
        self.preloader = ImagePreloader(max_size=20)  # 添加预加载器

    def test_endpoint(self, url: str, image_path: str) -> Tuple[bool, any, float]:
        """Test a single endpoint with an image and return timing."""
        start_time = time.time()
        try:
            # 使用预加载的图片数据
            _, image_base64 = self.preloader.get_next_image()
            
            # 构建JSON请求数据
            json_data = {
                "images": [image_base64]
            }
            
            # 发送JSON格式的POST请求
            headers = {'Content-Type': 'application/json'}
            response = requests.post(url, json=json_data, headers=headers)
            
            if response.status_code == 200:
                result = response.json()
                return True, result, time.time() - start_time
            else:
                return False, f"HTTP {response.status_code}: {response.text}", time.time() - start_time
                
        except Exception as e:
            return False, str(e), time.time() - start_time

    def process_batch(self, tasks: List[Tuple[str, str, bool]], max_workers: int) -> List[Tuple[bool, float]]:
        """Process a batch of images concurrently with specified number of workers."""
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for service_type, image_path, use_nginx in tasks:
                port = self.container_ports[service_type] if use_nginx else self.base_ports[service_type]
                url = f"http://127.0.0.1:{port}{self.api_paths[service_type]}"
                futures.append(executor.submit(self.test_endpoint, url, image_path))
            
            results = []
            for future in futures:
                success, result, duration = future.result()
                results.append((success, duration))
            return results

    def test_service(self, service_type: str, image_dir: str, use_nginx=False, concurrent=False, max_workers=5):
        """Test a specific service with all images in the directory."""
        port = self.container_ports[service_type] if use_nginx else self.base_ports[service_type]
        base_url = f"http://127.0.0.1:{port}{self.api_paths[service_type]}"
        
        logger.info(f"Testing {service_type} service at {base_url}")
        logger.info(f"Using {'Nginx load balancer' if use_nginx else 'direct service'}")
        logger.info(f"Mode: {'Concurrent' if concurrent else 'Sequential'}")

        success_count = 0
        total_count = 0
        durations = []
        
        image_files = [f for f in os.listdir(image_dir) 
                      if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
        image_paths = [os.path.join(image_dir, img) for img in image_files]

        # 启动预加载
        self.preloader.start_preloading(image_paths)
        
        try:
            if concurrent:
                tasks = [(service_type, path, use_nginx) 
                        for path in image_paths]
                results = self.process_batch(tasks, max_workers)
                
                for success, duration in results:
                    total_count += 1
                    if success:
                        success_count += 1
                    durations.append(duration)
            else:
                for image_path in image_paths:
                    total_count += 1
                    success, result, duration = self.test_endpoint(base_url, image_path)
                    
                    if success:
                        success_count += 1
                        logger.debug(f"Successfully processed {os.path.basename(image_path)}")
                    else:
                        logger.error(f"Failed to process {os.path.basename(image_path)}: {result}")
                    durations.append(duration)
        finally:
            # 停止预加载
            self.preloader.stop()

        timing_stats = {
            'mean': mean(durations),
            'median': median(durations),
            'std_dev': stdev(durations) if len(durations) > 1 else 0,
            'min': min(durations),
            'max': max(durations),
            'total': sum(durations)
        }

        return success_count, total_count, timing_stats

def test_thread_performance(test_dirs: List[str], services: List[str], use_nginx: bool):
    """Test performance with different thread counts and plot results."""
    thread_counts = range(1, 6)  # 1-5 threads
    performance_data = []
    
    tester = OCRServiceTester()
    
    for service, test_dir in zip(services, test_dirs):
        logger.info(f"\nTesting {service} service with different thread counts...")
        
        for thread_count in thread_counts:
            logger.info(f"Testing with {thread_count} threads...")
            success_count, total_count, timing_stats = tester.test_service(
                service, test_dir, use_nginx=use_nginx, 
                concurrent=True, max_workers=thread_count
            )
            
            performance_data.append({
                'service': service,
                'threads': thread_count,
                'mean_time': timing_stats['mean'],
                'total_time': timing_stats['total'],
                'success_rate': success_count/total_count*100
            })
    
    # Convert to DataFrame for easier plotting
    df = pd.DataFrame(performance_data)
    
    # Create performance plots
    plt.figure(figsize=(12, 6))
    
    # Plot mean time
    plt.subplot(1, 2, 1)
    for service in services:
        service_data = df[df['service'] == service]
        plt.plot(service_data['threads'], service_data['mean_time'], 
                marker='o', label=f'{service} mean time')
    plt.xlabel('Number of Threads')
    plt.ylabel('Mean Time (seconds)')
    plt.title('Mean Processing Time vs Thread Count')
    plt.legend()
    plt.grid(True)
    
    # Plot total time
    plt.subplot(1, 2, 2)
    for service in services:
        service_data = df[df['service'] == service]
        plt.plot(service_data['threads'], service_data['total_time'], 
                marker='o', label=f'{service} total time')
    plt.xlabel('Number of Threads')
    plt.ylabel('Total Time (seconds)')
    plt.title('Total Processing Time vs Thread Count')
    plt.legend()
    plt.grid(True)
    
    plt.tight_layout()
    plt.savefig('ocr_performance_analysis.png')
    plt.close()
    
    # Find optimal thread count for each service
    for service in services:
        service_data = df[df['service'] == service]
        optimal_threads = service_data.loc[service_data['mean_time'].idxmin()]['threads']
        logger.info(f"\nOptimal thread count for {service} service: {optimal_threads}")
        logger.info("Performance data:")
        logger.info(service_data.to_string(index=False))

def main():
    parser = argparse.ArgumentParser(description='Test OCR services')
    parser.add_argument('--test_dirs', type=str, required=True, nargs='+',
                       help='Directories containing test images (space-separated)')
    parser.add_argument('--services', type=str, nargs='+',
                       default=['system', 'vis', 'mrz'],
                       help='Services to test (space-separated)')
    parser.add_argument('--nginx', action='store_true',
                       help='Test Nginx load balanced endpoints')
    parser.add_argument('--concurrent', action='store_true',
                       help='Enable concurrent testing')
    parser.add_argument('--thread-analysis', action='store_true',
                       help='Perform thread count performance analysis')
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

    if args.thread_analysis:
        test_thread_performance(args.test_dirs, args.services, args.nginx)
    else:
        # Run tests for each service-directory pair
        for service, test_dir in zip(args.services, args.test_dirs):
            if service not in tester.base_ports:
                logger.error(f"Unknown service: {service}")
                continue
            
            logger.info(f"\nTesting {service} service with images from {test_dir}")
            success_count, total_count, timing_stats = tester.test_service(
                service, test_dir, use_nginx=args.nginx, concurrent=args.concurrent
            )
            
            logger.info(
                f"Results for {service}:\n"
                f"Success rate: {success_count}/{total_count} "
                f"({success_count/total_count*100:.2f}%)\n"
                f"Timing statistics (seconds):\n"
                f"  Mean: {timing_stats['mean']:.3f}\n"
                f"  Median: {timing_stats['median']:.3f}\n"
                f"  Std Dev: {timing_stats['std_dev']:.3f}\n"
                f"  Min: {timing_stats['min']:.3f}\n"
                f"  Max: {timing_stats['max']:.3f}\n"
                f"  Total: {timing_stats['total']:.3f}"
            )

if __name__ == "__main__":
    main()