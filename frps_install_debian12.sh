#!/bin/bash

# ==========================================
# 交互式 FRP Server Installer (带 IP 自动识别)
# Debian 12 / Ubuntu 适配
# ==========================================

FRP_VERSION="0.61.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 1. 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 root 权限运行此脚本。${PLAIN}"
   exit 1
fi

# 2. 收集用户配置 (交互部分)
clear
echo -e "${GREEN}=== FRP 服务端配置向导 ===${PLAIN}"

# 设置端口
read -p "请输入 frp 绑定端口 [默认 7000]: " input_port
FRPS_PORT=${input_port:-7000}

# 设置 Token
read -p "请输入连接 Token (留空则自动生成随机密钥): " input_token
if [[ -z "$input_token" ]]; then
    FRPS_TOKEN=$(openssl rand -hex 16)
else
    FRPS_TOKEN="$input_token"
fi

# 设置仪表盘用户
read -p "请输入仪表盘用户名 [默认 admin]: " input_user
DASHBOARD_USER=${input_user:-admin}

# 设置仪表盘密码
read -p "请输入仪表盘密码 (留空则自动生成随机密码): " input_pwd
if [[ -z "$input_pwd" ]]; then
    DASHBOARD_PWD=$(openssl rand -hex 8)
else
    DASHBOARD_PWD="$input_pwd"
fi

# 设置仪表盘端口
read -p "请输入仪表盘端口 [默认 7500]: " input_dash_port
DASHBOARD_PORT=${input_dash_port:-7500}

echo -e "\n${CYAN}即将使用以下配置安装:${PLAIN}"
echo -e "绑定端口: ${FRPS_PORT}"
echo -e "Token: ${FRPS_TOKEN}"
echo -e "仪表盘用户: ${DASHBOARD_USER}"
echo -e "仪表盘密码: ${DASHBOARD_PWD}"
echo -e "仪表盘端口: ${DASHBOARD_PORT}"
echo -e "------------------------------------------------"
read -n 1 -s -r -p "按任意键继续安装，或按 Ctrl+C 取消..."
echo ""

# 3. 安装依赖与环境检查
echo -e "${GREEN}正在准备环境...${PLAIN}"
apt-get update -y >/dev/null 2>&1
apt-get install -y wget tar curl openssl >/dev/null 2>&1

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    FRP_ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    FRP_ARCH="arm64"
else
    echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
    exit 1
fi

# 4. 下载并安装
WORKDIR="/tmp/frp_install"
mkdir -p $WORKDIR
cd $WORKDIR

DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
echo -e "${YELLOW}正在从 GitHub 下载 FRP v${FRP_VERSION}...${PLAIN}"

wget -N --no-check-certificate "$DOWNLOAD_URL"
if [[ ! -f "frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" ]]; then
    echo -e "${RED}下载失败，请检查网络。${PLAIN}"
    exit 1
fi

tar -zxvf "frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" >/dev/null 2>&1
cd "frp_${FRP_VERSION}_linux_${FRP_ARCH}"

cp frps /usr/local/bin/
chmod +x /usr/local/bin/frps

# 5. 生成配置文件
mkdir -p /etc/frp
cat > /etc/frp/frps.toml <<EOF
# frps.toml Config
bindPort = ${FRPS_PORT}

auth.method = "token"
auth.token = "${FRPS_TOKEN}"

webServer.addr = "0.0.0.0"
webServer.port = ${DASHBOARD_PORT}
webServer.user = "${DASHBOARD_USER}"
webServer.password = "${DASHBOARD_PWD}"
EOF

# 6. 配置 Systemd
cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=frp server
After=network.target syslog.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动服务
systemctl daemon-reload
systemctl enable frps
systemctl restart frps

# 清理
rm -rf $WORKDIR

# 8. 获取公网IP
echo -e "${GREEN}正在获取服务器公网 IP...${PLAIN}"
SERVER_IP=$(curl -s -4 --connect-timeout 5 checkip.amazonaws.com)
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="[自动获取失败，请手动填入IP]"
fi

# 9. 完成输出
echo -e "\n================================================"
if systemctl is-active --quiet frps; then
    echo -e "${GREEN}Frps 安装并启动成功！${PLAIN}"
    echo -e "配置文件路径: /etc/frp/frps.toml"
    
    echo -e "\n${YELLOW}>>> 仪表盘 (Dashboard)${PLAIN}"
    echo -e "地址: http://${SERVER_IP}:${DASHBOARD_PORT}"
    echo -e "账号: ${CYAN}${DASHBOARD_USER}${PLAIN}"
    echo -e "密码: ${RED}${DASHBOARD_PWD}${PLAIN}"
    
    echo -e "\n${YELLOW}>>> 客户端配置参考 (可以直接复制到 frpc.toml)${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "serverAddr = \"${SERVER_IP}\""
    echo -e "serverPort = ${FRPS_PORT}"
    echo -e ""
    echo -e "auth.method = \"token\""
    echo -e "auth.token = \"${FRPS_TOKEN}\""
    echo -e "------------------------------------------------"
    
    echo -e "\n${YELLOW}提示:${PLAIN} 如果无法连接，请检查云服务商防火墙是否放行了 ${FRPS_PORT} 和 ${DASHBOARD_PORT} 端口。"
else
    echo -e "${RED}Frps 启动失败，请使用 'journalctl -u frps --no-pager' 查看日志。${PLAIN}"
fi
echo -e "================================================"
