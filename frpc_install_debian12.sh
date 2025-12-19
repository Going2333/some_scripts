#!/bin/bash

# ==========================================
# FRP Client Installer for Debian 12 (Optimized for KCP)
# Author: Gemini
# Description: 用于本地 Debian 机器连接远程 frps，建立 SOCKS5 回国隧道
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${GREEN}正在初始化环境...${PLAIN}"
apt update -y
apt install -y curl wget tar nano

# ==========================================
# 1. 内核优化 (对本地上传速度至关重要)
# ==========================================
optimize_kernel() {
    echo -e "${YELLOW}>> [1/5] 正在优化 Linux 内核参数 (适配 KCP 上传)...${PLAIN}"

    cat > /etc/sysctl.d/99-frp-kcp.conf <<EOF
# --- FRP Client KCP Optimization ---
# 增大发送缓冲区 (Local -> Remote Upload)
net.core.wmem_default = 16777216
net.core.wmem_max = 16777216

# 增大接收缓冲区
net.core.rmem_default = 16777216
net.core.rmem_max = 16777216

# 增加队列长度
net.core.netdev_max_backlog = 10000

# 开启 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl -p /etc/sysctl.d/99-frp-kcp.conf > /dev/null 2>&1
    echo -e "${GREEN}✓ 内核优化完成！${PLAIN}"
}

# ==========================================
# 2. 收集配置信息
# ==========================================
collect_info() {
    echo -e "${YELLOW}>> [2/5] 请输入服务端 (frps) 信息：${PLAIN}"
    
    # 服务器 IP
    read -p "请输入 frps 服务器 IP 地址: " server_addr
    if [[ -z "${server_addr}" ]]; then
        echo -e "${RED}错误：必须输入服务器 IP！${PLAIN}"
        exit 1
    fi

    # 服务器端口
    read -p "请输入 frps 端口 [默认 7000]: " server_port
    [[ -z "${server_port}" ]] && server_port=7000

    # Token
    read -p "请输入连接 Token (需与服务端一致): " token
    if [[ -z "${token}" ]]; then
        echo -e "${RED}错误：必须输入 Token！${PLAIN}"
        exit 1
    fi

    echo -e "${YELLOW}>> 配置 SOCKS5 代理参数 (用于把本地网络映射出去)：${PLAIN}"
    
    # 远程映射端口
    read -p "请输入远程映射端口 (在 VPS 上访问的端口) [默认 10808]: " remote_port
    [[ -z "${remote_port}" ]] && remote_port=10808

    # SOCKS5 账号密码
    read -p "设置 SOCKS5 用户名 [默认 user]: " sock_user
    [[ -z "${sock_user}" ]] && sock_user="user"
    
    read -p "设置 SOCKS5 密码 [默认 pass]: " sock_pwd
    [[ -z "${sock_pwd}" ]] && sock_pwd="pass"
}

# ==========================================
# 3. 下载安装
# ==========================================
install_frp() {
    echo -e "${YELLOW}>> [3/5] 下载最新版 FRP...${PLAIN}"
    
    latest_version=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "${latest_version}" ]]; then
        latest_version="v0.61.0"
        echo -e "获取版本失败，使用默认: ${latest_version}"
    fi

    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        file_arch="amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        file_arch="arm64"
    else
        echo -e "${RED}不支持的架构: $arch${PLAIN}"
        exit 1
    fi

    version_num=${latest_version#v}
    wget -N --no-check-certificate "https://github.com/fatedier/frp/releases/download/${latest_version}/frp_${version_num}_linux_${file_arch}.tar.gz" -O frp.tar.gz
    
    tar -zxvf frp.tar.gz
    cd "frp_${version_num}_linux_${file_arch}"
    
    cp frpc /usr/bin/
    chmod +x /usr/bin/frpc
    mkdir -p /etc/frp
}

# ==========================================
# 4. 生成配置文件 (frpc.toml)
# ==========================================
configure_frp() {
    echo -e "${YELLOW}>> [4/5] 生成配置文件...${PLAIN}"
    
    cat > /etc/frp/frpc.toml <<EOF
# frpc.toml Config
serverAddr = "${server_addr}"
serverPort = ${server_port}

# 鉴权
auth.method = "token"
auth.token = "${token}"

# [关键] 开启 KCP 协议
transport.protocol = "kcp"

# 开启加密与压缩
transport.useEncryption = true
transport.useCompression = true

# SOCKS5 代理插件配置
[[proxies]]
name = "home_socks5_proxy"
type = "tcp"
remotePort = ${remote_port}

[proxies.plugin]
type = "socks5"
username = "${sock_user}"
password = "${sock_pwd}"
EOF
}

# ==========================================
# 5. 配置系统服务
# ==========================================
install_service() {
    echo -e "${YELLOW}>> [5/5] 配置 Systemd 服务...${PLAIN}"

    cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/bin/frpc -c /etc/frp/frpc.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frpc
    systemctl start frpc
}

# ==========================================
# 执行
# ==========================================
clear
echo "------------------------------------------------"
echo "   FRP Client 自动安装脚本 (Local/KCP版)        "
echo "------------------------------------------------"

optimize_kernel
collect_info
install_frp
configure_frp
install_service

cd ..
rm -rf frp.tar.gz "frp_${version_num}_linux_${file_arch}"

echo "------------------------------------------------"
echo -e "${GREEN}🎉 frpc 安装并启动成功！${PLAIN}"
echo "------------------------------------------------"
echo -e "连接状态检查: systemctl status frpc"
echo -e "日志查看命令: journalctl -u frpc -f"
echo "------------------------------------------------"
echo -e "现在，请在您的【国外 VPS】上使用以下代理进行测试："
echo -e "代理地址: 127.0.0.1:${remote_port}"
echo -e "账号: ${sock_user}"
echo -e "密码: ${sock_pwd}"
echo "------------------------------------------------"
