#!/bin/bash

# ==========================================
# FRP Server Installer for Debian 12 (Optimized for KCP)
# Author: Gemini (Optimized based on user request)
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${GREEN}正在初始化安装环境...${PLAIN}"
apt update -y
apt install -y curl wget tar nano

# ==========================================
# 核心函数：内核参数优化 (KCP/UDP 提速)
# ==========================================
optimize_kernel() {
    echo -e "${YELLOW}>> [1/5] 正在优化 Linux 内核参数以适配 KCP 协议...${PLAIN}"

    # 写入独立的配置文件，设置 UDP 缓冲区为 16MB
    cat > /etc/sysctl.d/99-frp-kcp.conf <<EOF
# --- FRP KCP Optimization Start ---
# 增加 UDP 接收缓冲区 (默认 & 最大 16MB)
net.core.rmem_default = 16777216
net.core.rmem_max = 16777216

# 增加 UDP 发送缓冲区 (默认 & 最大 16MB)
net.core.wmem_default = 16777216
net.core.wmem_max = 16777216

# 增加网络设备积压队列
net.core.netdev_max_backlog = 10000

# 开启 BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# --- FRP KCP Optimization End ---
EOF

    # 应用更改
    sysctl -p /etc/sysctl.d/99-frp-kcp.conf > /dev/null 2>&1
    echo -e "${GREEN}✓ 内核优化完成！UDP 缓冲区已扩展至 16MB。${PLAIN}"
}

# ==========================================
# 收集用户输入
# ==========================================
collect_info() {
    echo -e "${YELLOW}>> [2/5] 请输入配置信息：${PLAIN}"
    
    # 端口
    read -p "请输入 frp 服务端口 [默认 7000]: " bind_port
    [[ -z "${bind_port}" ]] && bind_port=7000
    
    # Token
    read -p "请输入连接密钥 (Token) [默认自动生成]: " token
    if [[ -z "${token}" ]]; then
        token=$(head -n 20 /dev/urandom | md5sum | head -c 16)
        echo -e "已自动生成 Token: ${GREEN}${token}${PLAIN}"
    fi

    # Dashboard 用户名
    read -p "请输入 Dashboard 管理用户名 [默认 admin]: " dashboard_user
    [[ -z "${dashboard_user}" ]] && dashboard_user="admin"

    # Dashboard 密码
    read -p "请输入 Dashboard 管理密码 [默认 admin]: " dashboard_pwd
    [[ -z "${dashboard_pwd}" ]] && dashboard_pwd="admin"

    # Dashboard 端口
    read -p "请输入 Dashboard 访问端口 [默认 7500]: " dashboard_port
    [[ -z "${dashboard_port}" ]] && dashboard_port=7500
}

# ==========================================
# 下载并安装 FRP
# ==========================================
install_frp() {
    echo -e "${YELLOW}>> [3/5] 正在获取最新版 FRP...${PLAIN}"
    
    # 获取最新版本号
    latest_version=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "${latest_version}" ]]; then
        echo -e "${RED}获取版本失败，使用默认版本 v0.61.0${PLAIN}"
        latest_version="v0.61.0"
    else
        echo -e "检测到最新版本：${GREEN}${latest_version}${PLAIN}"
    fi

    # 判断架构
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        file_arch="amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        file_arch="arm64"
    else
        echo -e "${RED}不支持的架构: $arch${PLAIN}"
        exit 1
    fi

    # 下载
    version_num=${latest_version#v} # 去掉v前缀
    download_url="https://github.com/fatedier/frp/releases/download/${latest_version}/frp_${version_num}_linux_${file_arch}.tar.gz"
    
    echo "正在下载: $download_url"
    wget -N --no-check-certificate "$download_url" -O frp.tar.gz
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败，请检查网络连接！${PLAIN}"
        exit 1
    fi

    # 解压安装
    tar -zxvf frp.tar.gz
    cd "frp_${version_num}_linux_${file_arch}"
    
    # 移动二进制文件
    cp frps /usr/bin/
    chmod +x /usr/bin/frps
    
    # 创建配置目录
    mkdir -p /etc/frp
}

# ==========================================
# 生成配置文件 (TOML 格式)
# ==========================================
configure_frp() {
    echo -e "${YELLOW}>> [4/5] 正在生成配置文件...${PLAIN}"
    
    cat > /etc/frp/frps.toml <<EOF
# frps.toml Config
bindPort = ${bind_port}

# [关键] 显式绑定 KCP 端口，开启 KCP 模式支持
kcpBindPort = ${bind_port}

# 鉴权配置
auth.method = "token"
auth.token = "${token}"

# Dashboard 面板
webServer.addr = "0.0.0.0"
webServer.port = ${dashboard_port}
webServer.user = "${dashboard_user}"
webServer.password = "${dashboard_pwd}"

# 允许的端口范围 (可选安全策略)
allowPorts = [
  { start = 1000, end = 65535 }
]
EOF
}

# ==========================================
# 配置 Systemd 服务
# ==========================================
install_service() {
    echo -e "${YELLOW}>> [5/5] 配置系统服务...${PLAIN}"

    cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/bin/frps -c /etc/frp/frps.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps
}

# ==========================================
# 主逻辑
# ==========================================
clear
echo "------------------------------------------------"
echo "   FRP Server 自动安装脚本 (Debian/UDP优化版)   "
echo "------------------------------------------------"

# 1. 优化内核
optimize_kernel
# 2. 收集信息
collect_info
# 3. 安装软件
install_frp
# 4. 写入配置
configure_frp
# 5. 启动服务
install_service

# 结束展示
cd ..
rm -rf frp.tar.gz "frp_${version_num}_linux_${file_arch}"

echo "------------------------------------------------"
echo -e "${GREEN}🎉 安装成功！FRP 服务已启动。${PLAIN}"
echo "------------------------------------------------"
echo -e "服务器端口 (TCP/UDP): ${GREEN}${bind_port}${PLAIN}"
echo -e "Token 密钥:           ${GREEN}${token}${PLAIN}"
echo -e "控制台地址:           http://IP:${dashboard_port}"
echo -e "控制台账号:           ${dashboard_user}"
echo -e "控制台密码:           ${dashboard_pwd}"
echo "------------------------------------------------"
echo -e "相关命令："
echo -e "修改配置: nano /etc/frp/frps.toml"
echo -e "重启服务: systemctl restart frps"
echo -e "查看状态: systemctl status frps"
echo "------------------------------------------------"
