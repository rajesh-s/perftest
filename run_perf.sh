export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com"
sudo apt update

# Kernel debug symbols
sudo tee /etc/apt/sources.list.d/ddebs.sources >/dev/null <<'EOF'
Types: deb
URIs: http://ddebs.ubuntu.com
Suites: noble noble-updates noble-proposed
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg
EOF
sudo apt update
sudo apt install -y \
  rdma-core-dbgsym libibverbs1-dbgsym librdmacm1t64-dbgsym \
  perftest-dbgsym
sudo apt install -y rdmacm-utils-dbgsym
sudo apt install -y linux-image-$(uname -r)-dbgsym


# Broadcom kernel driver debug symbols
sudo find /usr/lib/debug -path "*bnxt_re.ko*" -o -path "*bnxt_re.ko.debug*"
/usr/lib/debug/lib/modules/6.8.0-88-generic/kernel/drivers/infiniband/hw/bnxt_re/bnxt_re.ko.zst

# Broadcom userspace symbols
ls /usr/lib/*/libibverbs/libbnxt_re-rdmav*.so*
/usr/lib/aarch64-linux-gnu/libibverbs/libbnxt_re-rdmav34.so.inbox

sudo sysctl -w kernel.kptr_restrict=0
sudo sysctl -w kernel.perf_event_paranoid=-1


# If you built perftest yourself: add -fno-omit-frame-pointer -g for best stacks.