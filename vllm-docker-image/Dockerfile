# Use the NVIDIA PyTorch base image
FROM nvcr.io/nvidia/pytorch:24.07-py3

# Set environment variables to ensure pip installs packages in a clean, non-interactive way
ENV DEBIAN_FRONTEND=noninteractive

# Install required Python packages
RUN pip install vllm==0.6.1.post2 \
    && pip install opencv-python==4.6.0.66 \
    && pip uninstall -y pynvml \
    && pip install nvidia-ml-py==12.560.30

RUN pip install opencv-python-headless==4.6.0.66

# Set the default command for the container (optional)
CMD ["/bin/bash"]