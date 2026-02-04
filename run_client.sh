#!/bin/bash

# Script to run ib_write_bw test and capture output to CSV
# Usage: ./run_test_to_csv.sh <output_csv_file> [test_options...]
#
# Optional ftrace capture:
#   FTRACE=1 enables function graph tracing for post_send_method (default).
#   FTRACE_FUNC=post_send_method overrides the function filter.
#   FTRACE_OUT=/tmp/ftrace_post_send.txt sets output file for trace.

set -e

OUTPUT_CSV="${1:-results.csv}"
shift || true

# Default test parameters if none provided
if [ $# -eq 0 ]; then
    TEST_OPTS="-d roceP22p1s0 10.118.89.5 -x 3 -F --report_gbits -n 1000000 -Q 1024 -t 4096 -N --report-both --use_hugepages"
else
    TEST_OPTS="$@"
fi

# Temporary file to capture output
TEMP_OUTPUT="/tmp/ib_write_bw_output_$$.txt"
TEMP_PARSED="/tmp/ib_write_bw_parsed_$$.txt"

FTRACE="${FTRACE:-0}"
FTRACE_FUNC="${FTRACE_FUNC:-post_send_method}"
FTRACE_OUT="${FTRACE_OUT:-/tmp/ftrace_post_send_$$.txt}"

trace_dir=""
if [ -d /sys/kernel/tracing ]; then
    trace_dir="/sys/kernel/tracing"
elif [ -d /sys/kernel/debug/tracing ]; then
    trace_dir="/sys/kernel/debug/tracing"
fi

trace_sudo=""
if [ "$FTRACE" = "1" ] && [ "$(id -u)" -ne 0 ]; then
    trace_sudo="sudo"
fi

start_ftrace() {
    if [ "$FTRACE" != "1" ]; then
        return 0
    fi
    if [ -z "$trace_dir" ]; then
        echo "FTRACE=1 but tracefs is not available at /sys/kernel/tracing or /sys/kernel/debug/tracing"
        exit 1
    fi
    echo "Enabling ftrace function_graph for: $FTRACE_FUNC"
    $trace_sudo sh -c "echo 0 > $trace_dir/tracing_on"
    $trace_sudo sh -c "echo > $trace_dir/trace"
    $trace_sudo sh -c "echo nop > $trace_dir/current_tracer"
    $trace_sudo sh -c "echo function_graph > $trace_dir/current_tracer"
    $trace_sudo sh -c "echo $FTRACE_FUNC > $trace_dir/set_graph_function"
    $trace_sudo sh -c "echo 1 > $trace_dir/options/funcgraph-duration"
    $trace_sudo sh -c "echo 1 > $trace_dir/tracing_on"
}

stop_ftrace() {
    if [ "$FTRACE" != "1" ]; then
        return 0
    fi
    $trace_sudo sh -c "echo 0 > $trace_dir/tracing_on"
    $trace_sudo sh -c "cat $trace_dir/trace > $FTRACE_OUT"
    echo "Ftrace saved to: $FTRACE_OUT"
}

# Run the test and capture output
echo "Running test with options: $TEST_OPTS"
echo "Output will be saved to: $OUTPUT_CSV"
echo ""

start_ftrace
# sudo taskset -c 92 ./ib_write_bw $TEST_OPTS 2>&1 | tee "$TEMP_OUTPUT"
# sudo perf record -F 999 -g --call-graph fp -- \
# -a for all sizes
taskset -c 92 ./ib_write_bw $TEST_OPTS -s 16384 2>&1 | tee "$TEMP_OUTPUT"
stop_ftrace

# Parse the output
# Extract test configuration
TEST_DEVICE=$(grep "Device.*:" "$TEMP_OUTPUT" | head -1 | sed 's/.*Device[[:space:]]*:[[:space:]]*//' | awk '{print $1}')
TEST_TYPE=$(grep "RDMA_Write BW Test" "$TEMP_OUTPUT" || echo "RDMA_Write")
TEST_TRANSPORT=$(grep "Transport type" "$TEMP_OUTPUT" | head -1 | sed 's/.*Transport type[[:space:]]*:[[:space:]]*//' | awk '{print $1}')
TEST_CONNECTION=$(grep "Connection type" "$TEMP_OUTPUT" | head -1 | sed 's/.*Connection type[[:space:]]*:[[:space:]]*//' | awk '{print $1}')
TEST_MTU=$(grep "Mtu[[:space:]]*:" "$TEMP_OUTPUT" | head -1 | sed 's/.*Mtu[[:space:]]*:[[:space:]]*//' | awk '{print $1}')
TEST_TX_DEPTH=$(grep "TX depth" "$TEMP_OUTPUT" | head -1 | sed 's/.*TX depth[[:space:]]*:[[:space:]]*//' | awk '{print $1}')
TEST_ITERATIONS=$(grep "#iterations" "$TEMP_OUTPUT" | head -1 | awk '{print $NF}')

# Create CSV header
cat > "$OUTPUT_CSV" << EOF
# Test Configuration
# Device: $TEST_DEVICE
# Transport: $TEST_TRANSPORT
# Connection Type: $TEST_CONNECTION
# MTU: $TEST_MTU
# TX Depth: $TEST_TX_DEPTH
# Iterations: $TEST_ITERATIONS
# Command: ./ib_write_bw $TEST_OPTS
#
Bytes,Post Send Cycles/Iteration (ns),BW Peak (Gb/s),BW Average (Gb/s),Message Rate (Mpps)
EOF

# Parse data lines with cycle counts
awk '
/\*\*\*\*\* elapsed-post-send-cycles:/ {
    # Extract cycle count
    match($0, /elapsed-post-send-cycles: ([0-9]+)/, arr)
    cycles = arr[1]
    getline  # Read next line with the data
}
/^[[:space:]]+[0-9]+[[:space:]]+[0-9]+/ {
    # Parse data line: bytes, iterations, BW peak, BW average, MsgRate
    bytes = $1
    iterations = $2
    bw_peak = $3
    bw_avg = $4
    msg_rate = $5
    
    # Calculate cycles per iteration in nanoseconds
    # cycles_per_iter = cycles / iterations * (1e9 / 3e9) assuming 3GHz CPU
    # Or just: cycles / iterations in raw cycles, then convert to ns with CPU freq
    cycles_per_iter = cycles / iterations
    
    printf "%d,%ld,%.6f,%.6f,%.6f\n", bytes, cycles_per_iter, bw_peak, bw_avg, msg_rate
}
' "$TEMP_OUTPUT" >> "$OUTPUT_CSV"

# Display the CSV
echo ""
echo "====== CSV Output ======"
cat "$OUTPUT_CSV"
echo ""
echo "CSV saved to: $OUTPUT_CSV"

# Cleanup
rm -f "$TEMP_OUTPUT" "$TEMP_PARSED"
