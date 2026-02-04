# Performance Test with Instrumentation - Build and Run Guide

This document provides step-by-step instructions to apply the instrumentation patch, compile the perftest suite, and run the RDMA Write bandwidth benchmark test.

## Prerequisites

Ensure the following packages are installed on your system:

```bash
# Required development tools and libraries
sudo apt-get update
sudo apt-get install -y \
    autoconf \
    automake \
    libtool \
    build-essential \
    libibverbs-dev \
    librdmacm-dev \
    libumad-dev \
    libpci-dev

# Optional: for CUDA support (if needed)
# sudo apt-get install -y cuda-toolkit
```

## Step 1: Clone the Repository

If you haven't already cloned the repository:

```bash
git clone https://github.com/rajesh-s/perftest
cd perftest
```

## Step 2: Apply the Instrumentation Patch

Apply the provided patch file `instrumentation.patch` to add performance instrumentation:

```bash
git apply instrumentation.patch
```

### What the patch does:

The patch adds instrumentation to measure CPU cycles consumed by the send posting method:

1. **src/perftest_resources.c**:
   - Adds cycle counter tracking around `post_send_method()` in `run_iter_bw()`
   - Tracks total cycles spent in sending operations
   - Outputs: `elapsed-post-send-cycles: <value>`

2. **src/host_memory.c**:
   - Changes HUGEPAGE_ALIGN from 2MB to 1GB for better memory alignment
   - Improves performance with large hugepage configurations

## Step 3: Build

```bash
./autogen.sh
./configure
make -j4
```

## Step 6: Run the Instrumented Test

```bash
sudo taskset -c 92 ./ib_write_bw -d <device> <server_ip> \
    -x 3 \
    -F \
    --report_gbits \
    -a \
    -n 1000000 \
    -Q 1024 \
    -t 4096 \
    -N \
    --report-both \
    --use_hugepages
```

### Command Options Explained:

| Option | Description |
|--------|-------------|
| `-x 3` | Exchange 3 messages before starting test |
| `-F` | Flush (force completion processing) |
| `--report_gbits` | Report results in Gigabits per second |
| `-a` | Atomic operations |
| `-n 1000000` | Run 1 million iterations |
| `-Q 1024` | Queue depth (max outstanding requests) |
| `-t 4096` | Message/transfer size in bytes |
| `-N` | No peak (disable peak bandwidth calculation) |
| `--report-both` | Report both bandwidth and latency |
```