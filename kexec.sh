#!/usr/bin/env bash
set -euo pipefail

KERNEL_URL="https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
INITRD_URL="https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
WORK_DIR="/tmp/debian-kexec-install"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "错误：请使用 root 权限或 sudo 运行此脚本。" >&2
    exit 1
fi

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "[1/4] 更新软件源并安装 kexec-tools..."
apt update
apt install -y kexec-tools
command -v kexec >/dev/null 2>&1 || { echo "错误：kexec 未正确安装。" >&2; exit 1; }

echo "[2/4] 下载 Debian Trixie netboot 内核与 initrd..."
wget -q --show-progress -O linux "$KERNEL_URL"
wget -q --show-progress -O initrd.gz "$INITRD_URL"
test -s linux && test -s initrd.gz || { echo "错误：内核或 initrd 文件为空，下载可能失败。" >&2; exit 1; }

echo "[3/4] 加载新内核到内存..."
kexec -l ./linux --initrd=./initrd.gz --append="auto=true priority=critical"

echo ""
echo "=========================================================="
echo "警告：即将执行内核切换 (systemctl kexec)，机器将立即重启！"
echo "请在继续前手动打开 VNC / 远程控制台，以便查看安装界面。"
echo "=========================================================="
read -r -p "已打开 VNC 并确认立即重启进入安装程序？请输入 YES 继续: " confirm

if [[ "$confirm" == "YES" ]]; then
    echo "[4/4] 正在通过 kexec 切换内核并重启..."
    systemctl kexec
else
    echo "已取消操作。如需稍后切换，可进入 $WORK_DIR 后手动执行: systemctl kexec"
    exit 0
fi
