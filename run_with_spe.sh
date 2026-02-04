#!/bin/bash

# Script to run ib_write_bw with ARM SPE (Statistical Profiling Extension)
# ARM SPE provides detailed microarchitectural profiling on Grace CPUs

set -e

# Configuration
DEVICE="${DEVICE:-roceP22p1s0}"
SERVER_IP="${SERVER_IP:-10.118.89.5}"
SIZE="${SIZE:-16384}"  # 16K
ITERATIONS="${ITERATIONS:-100000}"
CPU_CORE="${CPU_CORE:-92}"
OUTPUT_DIR="${OUTPUT_DIR:-./spe_results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "=============================================="
echo " Perftest with ARM SPE Profiling on Grace"
echo "=============================================="
echo "Device:     $DEVICE"
echo "Server:     $SERVER_IP"  
echo "Size:       $SIZE bytes"
echo "Iterations: $ITERATIONS"
echo "CPU Core:   $CPU_CORE"
echo "=============================================="
echo ""

# Check if ARM SPE is available
if ! sudo perf list | grep -q "arm_spe"; then
    echo "WARNING: ARM SPE not detected. Falling back to regular perf."
    echo "To enable SPE, ensure:"
    echo "  1. Kernel has CONFIG_ARM_SPE_PMU=y"
    echo "  2. /sys/devices/arm_spe_0/ exists"
    echo ""
fi

TEST_CMD="./ib_write_bw -d $DEVICE $SERVER_IP -x 3 -F --report_gbits -s $SIZE -n $ITERATIONS -Q 1024 -N --report-both --use_hugepages"

# ============================================
# ARM SPE Recording
# ============================================
echo "[1/3] Recording with ARM SPE..."

# SPE events to capture:
# - arm_spe/ts_enable=1/ : Enable timestamps
# - arm_spe/load_filter=1/ : Filter load operations
# - arm_spe/store_filter=1/ : Filter store operations
# - arm_spe/branch_filter=1/ : Filter branches

sudo perf record -e arm_spe// \
    -C $CPU_CORE \
    -o "$OUTPUT_DIR/spe_record_${TIMESTAMP}.data" \
    -- taskset -c $CPU_CORE $TEST_CMD 2>&1 | tee "$OUTPUT_DIR/spe_output_${TIMESTAMP}.txt"

echo ""
echo "SPE data saved to: $OUTPUT_DIR/spe_record_${TIMESTAMP}.data"

# ============================================
# Generate SPE Report
# ============================================
echo ""
echo "[2/3] Generating SPE report..."

sudo perf report -i "$OUTPUT_DIR/spe_record_${TIMESTAMP}.data" \
    --stdio \
    --no-children \
    > "$OUTPUT_DIR/spe_report_${TIMESTAMP}.txt" 2>&1

echo "Report saved to: $OUTPUT_DIR/spe_report_${TIMESTAMP}.txt"

# ============================================
# Memory Access Analysis (SPE specific)
# ============================================
echo ""
echo "[3/3] Analyzing memory access patterns..."

sudo perf mem report -i "$OUTPUT_DIR/spe_record_${TIMESTAMP}.data" \
    --stdio \
    > "$OUTPUT_DIR/spe_mem_report_${TIMESTAMP}.txt" 2>&1 || echo "Memory report generation failed (may need newer perf)"

echo "Memory report saved to: $OUTPUT_DIR/spe_mem_report_${TIMESTAMP}.txt"

# ============================================
# Summary
# ============================================
echo ""
echo "=============================================="
echo " ARM SPE Profiling Complete!"
echo "=============================================="
echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR"/*${TIMESTAMP}*
echo ""
echo "To view interactive SPE report:"
echo "  sudo perf report -i $OUTPUT_DIR/spe_record_${TIMESTAMP}.data"
echo ""
echo "SPE provides:"
echo "  - Precise PC sampling"
echo "  - Load/Store latency attribution"
echo "  - Cache miss analysis"
echo "  - Branch misprediction analysis"
