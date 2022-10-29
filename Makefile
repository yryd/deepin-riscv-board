CROSS_COMPILE=riscv64-linux-gnu-
ARCH=riscv
SKIP_INSTALL_PACKAGE=no
HOME=$$(pwd)
OUT_DIR=$(HOME)/output
DEVICE=/dev/loop100
DISTURB=deepin
DEEPIN_REPO=https://mirror.iscas.ac.cn/deepin-riscv/deepin-stage1/

all: test_machine_info

test_machine_info:
	uname -a
    echo $$(nproc)
    lscpu
    whoami
    env
    mkdir -p $(OUT_DIR)
