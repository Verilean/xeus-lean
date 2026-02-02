# Dockerfile for xeus-lean
FROM ubuntu:22.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    cmake \
    nlohmann-json3-dev \
    libzmq3-dev \
    libcppzmq-dev \
    python3 \
    python3-pip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Lean via elan
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

# Install Jupyter client for testing
RUN pip3 install jupyter-client

# Set working directory
WORKDIR /app

# Copy project files
COPY . /app/

# Verify Lean installation and version
RUN lean --version && lake --version

# Build C++ FFI library
RUN mkdir -p build-cmake && \
    cd build-cmake && \
    cmake .. && \
    cmake --build .

# Build Lean kernel
RUN lake build xlean

# Verify build artifacts
RUN ls -lh build-cmake/libxeus_ffi.a && \
    ls -lh .lake/build/bin/xlean && \
    file .lake/build/bin/xlean

# Set up environment
ENV XLEAN_PATH=/app/.lake/build/bin/xlean

# Default command
CMD ["/bin/bash"]
