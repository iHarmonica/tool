#!/usr/bin/env bash
set -u

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# 逐条确认：输入 y/Y 执行，q/Q 退出整个脚本，其余跳过当前项
confirm() {
    local desc="$1"
    local ans=""
    echo ""
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${YELLOW}[待确认]${NC} ${desc}"
    read -r -p "是否执行？[y/N/q]: " ans </dev/tty
    case "${ans}" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        [qQ]|[qQ][uU][iI][tT])
            echo -e "${RED}已手动退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo "已跳过。"
            return 1
            ;;
    esac
}

# 获取当前时区字符串
get_timezone() {
    local tz=""
    tz=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone/{print $2}' | awk '{print $1}' || true)
    if [ -z "${tz}" ] && [ -f /etc/timezone ]; then
        tz=$(cat /etc/timezone 2>/dev/null || true)
    fi
    if [ -z "${tz}" ]; then
        tz=$(date +%Z 2>/dev/null || echo "未知")
    fi
    echo "${tz}"
}

# 应用并校验时区
apply_timezone() {
    local tz="$1"
    tz="${tz// /}"
    if [ -z "${tz}" ]; then
        echo -e "${RED}时区不能为空，请重新输入。${NC}"
        return 1
    fi
    if [ -f "/usr/share/zoneinfo/${tz}" ]; then
        timedatectl set-timezone "${tz}"
        echo -e "${GREEN}时区已修改为 ${tz}，当前时间: $(date "+%Y-%m-%d %H:%M:%S %Z (%z)")${NC}"
        return 0
    else
        echo -e "${RED}无效时区 ${tz}（未找到 /usr/share/zoneinfo/${tz}），请重新输入。${NC}"
        return 1
    fi
}

# 简单判断是否可能为 AWS 实例（仅作辅助提示，最终仍由你确认）
is_likely_aws() {
    local sys_vendor="" prod_name="" bios_ver=""
    sys_vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || true)
    prod_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)
    bios_ver=$(cat /sys/devices/virtual/dmi/id/bios_version 2>/dev/null || true)

    if echo "${sys_vendor} ${prod_name} ${bios_ver}" | grep -qiE "amazon|aws|ec2"; then
        return 0
    fi
    if [ -d /var/lib/cloud/instances ] && ls /var/lib/cloud/instances/ 2>/dev/null | grep -qE "^i-"; then
        return 0
    fi
    return 1
}

current_tz=$(get_timezone)
echo -e "${GREEN}=== VPS 交互式运维脚本启动 ===${NC}"
echo "主机: $(hostname) | 系统: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" || uname -s)"
echo -e "当前时区: ${CYAN}${current_tz}${NC} | 当前时间: ${CYAN}$(date "+%Y-%m-%d %H:%M:%S %Z (%z)")${NC}"

# 启动时显示时区并询问是否修改（数字快捷选项 + 手动输入）
if confirm "是否修改当前系统时区（当前: ${current_tz}）"; then
    tz_choice=""
    while true; do
        echo "请选择目标时区（输入 q 取消修改）："
        echo "  1) 东京 (Asia/Tokyo)"
        echo "  2) 香港 (Asia/Hong_Kong)"
        echo "  3) 新加坡 (Asia/Singapore)"
        echo "  4) 伦敦 (Europe/London)"
        echo "  5) 纽约 (America/New_York)"
        echo "  6) 洛杉矶 (America/Los_Angeles)"
        echo "  7) 其他手动输入"
        read -r -p "请输入选项 [1-7/q]: " tz_choice </dev/tty
        case "${tz_choice}" in
            1)
                apply_timezone "Asia/Tokyo" && break
                ;;
            2)
                apply_timezone "Asia/Hong_Kong" && break
                ;;
            3)
                apply_timezone "Asia/Singapore" && break
                ;;
            4)
                apply_timezone "Europe/London" && break
                ;;
            5)
                apply_timezone "America/New_York" && break
                ;;
            6)
                apply_timezone "America/Los_Angeles" && break
                ;;
            7)
                while true; do
                    read -r -p "请输入时区（如 Asia/Shanghai，输入 q 返回上一级）: " manual_tz </dev/tty
                    case "${manual_tz}" in
                        [qQ]|[qQ][uU][iI][tT])
                            break
                            ;;
                    esac
                    if apply_timezone "${manual_tz}"; then
                        break 2
                    fi
                done
                ;;
            [qQ]|[qQ][uU][iI][tT])
                echo "已取消修改时区。"
                break
                ;;
            *)
                echo -e "${RED}输入无效，请输入 1-7 或 q 取消。${NC}"
                ;;
        esac
    done
fi

# 01 | AWS 修改 hostname 和 DNS【按需确认 · 适合 AWS 实例】
if is_likely_aws; then
    aws_hint="检测到当前环境可能为 AWS"
else
    aws_hint="未明显检测到 AWS 特征（非 AWS 机器通常跳过）"
fi

if confirm "01 | AWS 修改 hostname 和 DNS [${aws_hint}]"; then
    sudo hostnamectl set-hostname localhost \
        && sed -i \
            's/^preserve_hostname:.*/preserve_hostname: true/' \
            /etc/cloud/cloud.cfg \
        && sed -i \
            -e 's/^#\?DNS=.*/DNS=1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888/' \
            -e 's/^#\?Domains=.*/Domains=~./' \
            /etc/systemd/resolved.conf \
        && systemctl restart systemd-resolved \
        && echo -e "${GREEN}AWS hostname 与 DNS 已更新。${NC}"
fi

# 02 | 系统更新与常用软件安装【全量必跑】
if confirm "02 | 系统更新与常用软件安装 [全量必跑]"; then
    apt update && apt upgrade -y && \
    apt install -y curl wget vim unzip zip htop tmux tree lsof nginx certbot python3-certbot-nginx whois cron mtr-tiny iputils-ping procps socat sudo iftop git
fi

# 03 | 开启 BBR TCP 拥塞控制【按需确认 · 含 sysctl 失败时补全 PATH 并重试】
if confirm "03 | 开启 BBR TCP 拥塞控制 (fq + bbr + tfo=3)"; then
    cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF

    if ! sysctl --system; then
        echo -e "${YELLOW}sysctl --system 执行异常，尝试补全 /root/.bashrc 的 PATH 后重试...${NC}"
        path_line='export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        grep -qxF "${path_line}" /root/.bashrc 2>/dev/null || echo "${path_line}" >> /root/.bashrc
        # shellcheck disable=SC1090
        source /root/.bashrc
        sysctl --system
    fi
fi

# 04 | 开启 zram 并优化【按需确认 · 视内存与场景取舍】
if confirm "04 | 开启 zram 并优化 (zram-tools + vm.swappiness=100)"; then
    apt install -y zram-tools && systemctl enable --now zramswap \
    && echo "vm.swappiness=100" > /etc/sysctl.d/99-swappiness.conf \
    && sysctl --system \
    && systemctl status zramswap --no-pager && swapon --show && free -h
fi

# 05 | 限制系统日志容量【按需确认】
if confirm "05 | 限制系统日志容量 (128M / 64M / 1week)"; then
    sed -i -e 's|#SystemMaxUse=.*|SystemMaxUse=128M|' \
           -e 's|#RuntimeMaxUse=.*|RuntimeMaxUse=64M|' \
           -e 's|#MaxRetentionSec=.*|MaxRetentionSec=1week|' \
           /etc/systemd/journald.conf \
    && systemctl restart systemd-journald
fi

# 06 | 申请域名证书（支持连续申请多张，直到选择不继续）
first_cert_prompt=1
while true; do
    if [ "${first_cert_prompt}" -eq 1 ]; then
        prompt_desc="06 | 申请域名证书 (Certbot + Nginx)"
        first_cert_prompt=0
    else
        prompt_desc="06 | 是否还要再申请域名证书？(Certbot + Nginx)"
    fi

    if ! confirm "${prompt_desc}"; then
        break
    fi

    cert_mode=""
    cert_cancelled=0
    while true; do
        echo "请选择证书模式（输入 q 返回主流程）："
        echo "  1) 申请证书并启用 HTTPS 访问（自动跳转 --redirect）"
        echo "  2) 仅申请证书（certonly，如 Komari/m，ocserv/us）"
        read -r -p "请输入选项 [1/2/q]: " cert_mode </dev/tty
        case "${cert_mode}" in
            1|2)
                break
                ;;
            [qQ]|[qQ][uU][iI][tT])
                echo "已取消本次证书申请。"
                cert_cancelled=1
                break
                ;;
            *)
                echo -e "${RED}输入无效，请仅输入 1、2 或 q 返回。${NC}"
                ;;
        esac
    done

    if [ "${cert_cancelled}" -eq 0 ]; then
        domain_name=""
        while true; do
            if [ "${cert_mode}" = "2" ]; then
                read -r -p "请输入域名（仅申请证书，如 Komari/m，ocserv/us 对应域名，输入 q 返回）: " domain_name </dev/tty
            else
                read -r -p "请输入域名（例如 example.com，输入 q 返回）: " domain_name </dev/tty
            fi
            case "${domain_name}" in
                [qQ]|[qQ][uU][iI][tT])
                    echo "已取消本次证书申请。"
                    cert_cancelled=1
                    break
                    ;;
            esac
            domain_name="${domain_name// /}"
            if [[ -n "${domain_name}" && "${domain_name}" == *.* ]]; then
                break
            fi
            echo -e "${RED}域名格式不正确，请重新输入（或输入 q 返回）。${NC}"
        done
    fi

    if [ "${cert_cancelled}" -eq 0 ]; then
        if [ "${cert_mode}" = "1" ]; then
            certbot --nginx --email i@admin.com --agree-tos --no-eff-email -d "${domain_name}" --redirect
        else
            certbot certonly --nginx --email i@admin.com --agree-tos --no-eff-email -d "${domain_name}"
        fi
    fi
done

# 07 | 安装 3x-ui 面板【按需确认】
if confirm "07 | 安装 3x-ui 面板"; then
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
fi

# 08 | Komari 探针主机部署与反代配置【按需确认】
if confirm "08 | 是否为 Komari 探针主机（安装 Komari）"; then
    bash <(curl -Ls https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh)

    if confirm "08-A | 是否为 Komari 添加 Nginx 反向代理"; then
        komari_domain=""
        while true; do
            read -r -p "请输入绑定的域名（例如 m.cucc.me）: " komari_domain </dev/tty
            komari_domain="${komari_domain// /}"
            if [[ -n "${komari_domain}" && "${komari_domain}" == *.* ]]; then
                break
            fi
            echo -e "${RED}域名格式不正确，请重新输入。${NC}"
        done

        komari_port=""
        while true; do
            echo -e "${YELLOW}提示：端口通常设置为 8020（直接回车默认使用 8020）。${NC}"
            read -r -p "请输入后端端口 [默认 8020]: " komari_port </dev/tty
            komari_port="${komari_port:-8020}"
            komari_port="${komari_port// /}"
            if [[ "${komari_port}" =~ ^[0-9]+$ ]] && [ "${komari_port}" -ge 1 ] && [ "${komari_port}" -le 65535 ]; then
                break
            fi
            echo -e "${RED}端口无效，请输入 1-65535 之间的数字。${NC}"
        done

        site_conf="/etc/nginx/sites-available/${komari_domain}"
        cat <<EOF > "${site_conf}"
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${komari_domain};

    ssl_certificate /etc/letsencrypt/live/${komari_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${komari_domain}/privkey.pem;

    # 遵照官网：直接对全站路径进行全功能代理
    location / {
        # 后端端口 ${komari_port}
        proxy_pass http://127.0.0.1:${komari_port};

        # 基础透传头部
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 核心：全面启用 WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";

        # 官网推荐的其他优化参数
        proxy_buffering off;
        client_max_body_size 50M;
    }
}

# HTTP 自动跳转到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${komari_domain};
    return 301 https://\$host\$request_uri;
}
EOF

        ln -sfn "${site_conf}" "/etc/nginx/sites-enabled/${komari_domain}"
        nginx -t && nginx -s reload && systemctl restart nginx
    fi

    echo -e "${GREEN}Komari 部署/反代步骤已完成：请打开网页，按照安装向导设置用户名和密码完成安装。${NC}"
fi

# 09 | 安装并配置 ocserv【按需确认】
if confirm "09 | 是否安装 ocserv（端口 8800，同时安装 nftables）"; then
    # 1. 安装 ocserv 与 nftables
    apt install -y ocserv nftables

    # 2. 开启转发
    cat >/etc/sysctl.d/99-forward.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
    sysctl --system

    # 3. 查看网卡名称并配置 nftables 转发策略
    echo -e "${CYAN}当前网络接口信息（ip -c a）：${NC}"
    ip -c a

    default_nic=$(ip -o route show default 2>/dev/null | awk '{print $5}' | head -n 1 || true)
    nic_name=""
    while true; do
        if [ -n "${default_nic}" ]; then
            read -r -p "请输入出站网卡名称（如 ens5，直接回车默认 ${default_nic}）: " nic_name </dev/tty
            nic_name="${nic_name:-$default_nic}"
        else
            read -r -p "请输入出站网卡名称（如 ens5）: " nic_name </dev/tty
        fi
        nic_name="${nic_name// /}"
        if [ -n "${nic_name}" ]; then
            break
        fi
        echo -e "${RED}网卡名称不能为空，请重新输入。${NC}"
    done

    systemctl enable nftables --now
    cat >/etc/nftables.conf <<EOF
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "${nic_name}" masquerade
  }
}
EOF
    nft -f /etc/nftables.conf
    nft list ruleset

    # 4. 下载 ocserv.conf / ca.pem / user.p12
    B="https://raw.githubusercontent.com/iHarmonica/tool/main"
    [ -f /etc/ocserv/ocserv.conf ] && mv /etc/ocserv/ocserv.conf /etc/ocserv/ocserv.conf.bak
    mkdir -p /etc/ocserv /var/www/html
    wget -P /etc/ocserv/ "${B}/ocserv.conf" "${B}/ca.pem"
    wget -P /var/www/html/ "${B}/user.p12"

    # 5. 设置开机启动
    systemctl enable ocserv

    # 6. 定时重启（按当前时区与 24 小时制输入“周几 小时”，如周一上午5点输入 1 5）
    tz_info=$(get_timezone)
    now_time=$(date "+%Y-%m-%d %H:%M:%S %Z (%z)")

    cron_summary="未配置定时重启"
    while true; do
        echo ""
        echo -e "${YELLOW}当前本机时区：${tz_info}${NC}"
        echo -e "${YELLOW}当前本机时间：${now_time}（请按 24 小时制输入）${NC}"
        echo "请输入每周几几点重启（格式：周几 小时，用空格隔开；周日可用 0 或 7，周一到周六为 1-6；例如每周一上午5点输入：1 5；输入 q 跳过）："
        read -r -p "请输入 [周几 小时/q]: " cron_input </dev/tty
        case "${cron_input}" in
            [qQ]|[qQ][uU][iI][tT])
                echo "已跳过定时重启配置。"
                break
                ;;
        esac

        read -r cron_dow cron_hour extra_part <<< "${cron_input}"
        if [ -z "${extra_part:-}" ] \
            && [[ "${cron_dow:-}" =~ ^[0-7]$ ]] \
            && [[ "${cron_hour:-}" =~ ^([01]?[0-9]|2[0-3])$ ]]; then
            cron_hour_num=$((10#${cron_hour}))
            cron_line="0 ${cron_hour_num} * * ${cron_dow} /usr/bin/systemctl restart ocserv"
            existing_cron=$(crontab -l 2>/dev/null || true)
            {
                printf "%s\n" "${existing_cron}" | grep -vF "/usr/bin/systemctl restart ocserv" || true
                printf "%s\n" "${cron_line}"
            } | awk 'NF' | crontab -
            cron_summary="时区: ${tz_info} | 规则: 每周 ${cron_dow} 第 ${cron_hour_num} 点（0 ${cron_hour_num} * * ${cron_dow}）"
            echo -e "${GREEN}已写入定时任务：${cron_line}${NC}"
            break
        else
            echo -e "${RED}输入格式无效，请按“周几 小时”（如 1 5，小时 0-23）输入，或输入 q 跳过。${NC}"
        fi
    done

    # 7. 查看域名证书 SHA1 指纹（转为无符号小写）
    ocserv_domain=""
    sha1_lower=""
    while true; do
        read -r -p "请输入 ocserv 证书对应的域名（如 us.cucc.me，输入 q 跳过证书指纹查看）: " ocserv_domain </dev/tty
        case "${ocserv_domain}" in
            [qQ]|[qQ][uU][iI][tT])
                echo "已跳过证书 SHA1 指纹查看。"
                break
                ;;
        esac
        ocserv_domain="${ocserv_domain// /}"
        cert_file="/etc/letsencrypt/live/${ocserv_domain}/cert.pem"
        if [ -n "${ocserv_domain}" ] && [ -f "${cert_file}" ]; then
            raw_fp=$(openssl x509 -sha1 -in "${cert_file}" -noout -fingerprint)
            echo "${raw_fp}"
            sha1_lower=$(echo "${raw_fp}" | sed -E 's/^.*=//; s/://g' | tr '[:upper:]' '[:lower:]')
            break
        else
            echo -e "${RED}未找到证书文件 ${cert_file}，请重新输入域名或输入 q 跳过。${NC}"
        fi
    done

    # 8. 重启并查看 ocserv 状态
    service ocserv restart
    systemctl status ocserv --no-pager

    echo ""
    echo -e "${GREEN}=== ocserv 配置汇总 ===${NC}"
    if [ -n "${sha1_lower}" ]; then
        echo -e "证书 SHA1 指纹（小写无符号）: ${CYAN}${sha1_lower}${NC}"
    else
        echo -e "证书 SHA1 指纹（小写无符号）: ${YELLOW}未生成${NC}"
    fi
    echo -e "定时重启设置: ${CYAN}${cron_summary}${NC}"
fi

echo ""
echo -e "${GREEN}=== 所有任务流程已处理完毕 ===${NC}"
