#!/bin/bash

# Script to run ib_write_bw with perf profiling on ARM Grace
# Profiles both userspace and kernel functions during the benchmark

set -e

# Configuration
DEVICE="${DEVICE:-roceP22p1s0}"
SERVER_IP="${SERVER_IP:-10.118.89.5}"
SIZE="${SIZE:-16384}"  # 16K
ITERATIONS="${ITERATIONS:-100000}"
CPU_CORE="${CPU_CORE:-92}"
OUTPUT_DIR="${OUTPUT_DIR:-./perf_results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "=============================================="
echo " Perftest with Perf Profiling on ARM Grace"
echo "=============================================="
echo "Device:     $DEVICE"
echo "Server:     $SERVER_IP"
echo "Size:       $SIZE bytes"
echo "Iterations: $ITERATIONS"
echo "CPU Core:   $CPU_CORE"
echo "Output Dir: $OUTPUT_DIR"
echo "=============================================="
echo ""

# Build command
TEST_CMD="./ib_write_bw -d $DEVICE $SERVER_IP -x 3 -F --report_gbits -s $SIZE -n $ITERATIONS -Q 1024 -N --report-both --use_hugepages"

# ============================================
# Method 1: perf stat - Get aggregate statistics
# ============================================
echo "[1/4] Running perf stat for aggregate CPU metrics..."

sudo perf stat -e cycles,instructions,cache-references,cache-misses,branch-instructions,branch-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses \
    -C $CPU_CORE \
    taskset -c $CPU_CORE $TEST_CMD 2>&1 | tee "$OUTPUT_DIR/perf_stat_${TIMESTAMP}.txt"

echo ""
echo "Stats saved to: $OUTPUT_DIR/perf_stat_${TIMESTAMP}.txt"

# ============================================
# Method 2: perf record - Function-level profiling
# ============================================
echo ""
echo "[2/4] Running perf record for call graph analysis..."

sudo perf record -g --call-graph dwarf -F 9999 -C $CPU_CORE -o "$OUTPUT_DIR/perf_record_${TIMESTAMP}.data" -- \
    taskset -c $CPU_CORE $TEST_CMD 2>&1 | tee "$OUTPUT_DIR/perf_record_output_${TIMESTAMP}.txt"

echo ""
echo "Generating perf report..."
sudo perf report -i "$OUTPUT_DIR/perf_record_${TIMESTAMP}.data" --stdio --no-children > "$OUTPUT_DIR/perf_report_${TIMESTAMP}.txt" 2>&1

echo "Report saved to: $OUTPUT_DIR/perf_report_${TIMESTAMP}.txt"

# ============================================
# Method 3: perf annotate - Source-level breakdown
# ============================================
echo ""
echo "[3/4] Generating source annotation (requires debug symbols)..."

sudo perf annotate -i "$OUTPUT_DIR/perf_record_${TIMESTAMP}.data" --stdio > "$OUTPUT_DIR/perf_annotate_${TIMESTAMP}.txt" 2>&1 || true

echo "Annotation saved to: $OUTPUT_DIR/perf_annotate_${TIMESTAMP}.txt"

# ============================================
# Method 4: Flame Graph generation
# ============================================
echo ""
echo "[4/4] Generating Flame Graph..."

# Check if FlameGraph tools exist
if [ -d "/opt/FlameGraph" ]; then
    FLAMEGRAPH_DIR="/opt/FlameGraph"
elif [ -d "$HOME/FlameGraph" ]; then
    FLAMEGRAPH_DIR="$HOME/FlameGraph"
else
    echo "FlameGraph tools not found. Skipping flame graph generation."
    echo "To install: git clone https://github.com/brendangregg/FlameGraph.git ~/FlameGraph"
    FLAMEGRAPH_DIR=""
fi

if [ -n "$FLAMEGRAPH_DIR" ]; then
    sudo perf script -i "$OUTPUT_DIR/perf_record_${TIMESTAMP}.data" > "$OUTPUT_DIR/perf_script_${TIMESTAMP}.out" 2>/dev/null
    $FLAMEGRAPH_DIR/stackcollapse-perf.pl "$OUTPUT_DIR/perf_script_${TIMESTAMP}.out" > "$OUTPUT_DIR/folded_${TIMESTAMP}.out" 2>/dev/null
    $FLAMEGRAPH_DIR/flamegraph.pl "$OUTPUT_DIR/folded_${TIMESTAMP}.out" > "$OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg" 2>/dev/null
    echo "Flame graph saved to: $OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg"
fi

echo ""
echo "=============================================="
echo " Profiling Complete!"
echo "=============================================="
echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR"/*${TIMESTAMP}*
echo ""
echo "To view interactive report:"
echo "  sudo perf report -i $OUTPUT_DIR/perf_record_${TIMESTAMP}.data"
echo ""
echo "To view flame graph (if generated):"
echo "  firefox $OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg"
