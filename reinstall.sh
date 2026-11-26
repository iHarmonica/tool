#!/usr/bin/env bash
set -euo pipefail

KERNEL_URL="https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
INITRD_URL="https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
KEXEC_DIR="/tmp/debian-kexec-install"
REINSTALL_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
OSMUTATION_URL="https://raw.githubusercontent.com/LloydAsp/OsMutation/main/OsMutation.sh"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "错误：请使用 root 权限或 sudo 运行此脚本。" >&2
    exit 1
fi

detect_lxc() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt_type=$(systemd-detect-virt 2>/dev/null || true)
        if [[ "$virt_type" == "lxc" || "$virt_type" == "lxc-libvirt" ]]; then
            return 0
        fi
    fi

    if [[ -f /run/systemd/container ]] && grep -qiE "lxc" /run/systemd/container 2>/dev/null; then
        return 0
    fi

    if [[ -f /proc/1/environ ]] && tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -qiE "^container=lxc"; then
        return 0
    fi

    if [[ -f /proc/self/status ]] && grep -qiE "^envID:\s*[1-9]" /proc/self/status 2>/dev/null; then
        return 0
    fi

    return 1
}

run_kexec_flow() {
    mkdir -p "$KEXEC_DIR"
    cd "$KEXEC_DIR"

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
        echo "已取消操作。如需稍后切换，可进入 $KEXEC_DIR 后手动执行: systemctl kexec"
        exit 0
    fi
}

run_bin456789_flow() {
    local work_dir="/root/reinstall-bin456789"
    mkdir -p "$work_dir"
    cd "$work_dir"

    echo "正在下载 reinstall.sh ..."
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -O "$REINSTALL_URL" || wget -O "reinstall.sh" "$REINSTALL_URL"
    else
        wget -O "reinstall.sh" "$REINSTALL_URL"
    fi

    test -s "reinstall.sh" || { echo "错误：reinstall.sh 下载失败或为空。" >&2; exit 1; }
    chmod +x "reinstall.sh"

    echo ""
    echo "reinstall.sh 下载完成！请选择后续重装方式："
    echo "  1) 自己输入命令重装"
    echo "  2) 重启到 netboot.xyz 重装"
    read -r -p "请输入选项 [1/2]: " sub_choice

    case "$sub_choice" in
        1)
            echo ""
            echo "请输入你要执行的重装命令，例如："
            echo "  bash reinstall.sh debian 13 --ssh-port 1234"
            echo ""
            read -r -p "请输入命令: " custom_cmd
            if [[ -z "${custom_cmd// }" ]]; then
                echo "未输入命令，已退出。"
                exit 1
            fi
            echo "即将执行：$custom_cmd"
            eval "$custom_cmd"
            ;;
        2)
            echo ""
            echo "=========================================================="
            echo "提示：即将重启进入 netboot.xyz，请务必提前打开 VNC / 控制台！"
            echo "=========================================================="
            read -r -p "确认已打开 VNC 并继续执行（输入 y 确认）: " netboot_confirm
            if [[ "$netboot_confirm" == "y" || "$netboot_confirm" == "Y" ]]; then
                bash reinstall.sh netboot.xyz
            else
                echo "已取消执行。"
                exit 0
            fi
            ;;
        *)
            echo "无效输入，已退出。" >&2
            exit 1
            ;;
    esac
}

run_lxc_flow() {
    if ! detect_lxc; then
        echo "当前机器不是 LXC 环境，已取消执行 LXC 重装命令。" >&2
        exit 1
    fi

    local work_dir="/root/lxc-osmutation"
    mkdir -p "$work_dir"
    cd "$work_dir"

    echo "正在下载并运行 OsMutation.sh ..."
    wget -qO OsMutation.sh "$OSMUTATION_URL" && chmod u+x OsMutation.sh && ./OsMutation.sh
}

if detect_lxc; then
    echo "=========================================================="
    echo "检测到当前环境疑似 LXC 容器！"
    echo "建议优先选择【3) LXC 重装】，传统 kexec 内核切换通常不适用于 LXC。"
    echo "=========================================================="
fi

echo "请选择重装系统方式："
echo "  1) VNC kexec 方式（Debian Trixie netboot）"
echo "  2) bin456789 脚本方式（reinstall.sh）"
echo "  3) LXC 重装（OsMutation.sh）"
read -r -p "请输入数字 [1/2/3]: " main_choice

case "$main_choice" in
    1)
        run_kexec_flow
        ;;
    2)
        run_bin456789_flow
        ;;
    3)
        run_lxc_flow
        ;;
    *)
        echo "无效选项，请输入 1、2 或 3。" >&2
        exit 1
        ;;
esac
