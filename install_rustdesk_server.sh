#!/bin/bash

# ==================================================
# RustDesk Server Installer for Debian 12
# Author: Gemini
# Description: Install hbbs & hbbr with Systemd
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${GREEN}>>> 正在初始化环境...${PLAIN}"
apt update -y
apt install -y curl wget unzip tar ufw

# ==================================================
# 1. 设置安装参数
# ==================================================
INSTALL_DIR="/opt/rustdesk"

echo -e "${YELLOW}>>> [1/4] 配置服务器参数${PLAIN}"

# 自动获取公网 IP
WAN_IP=$(curl -s -4 ifconfig.me)
read -p "请输入服务器公网 IP 或域名 [默认: ${WAN_IP}]: " SERVER_IP
[[ -z "${SERVER_IP}" ]] && SERVER_IP="${WAN_IP}"

echo -e "服务器地址已设置为: ${GREEN}${SERVER_IP}${PLAIN}"

# ==================================================
# 2. 下载 RustDesk Server
# ==================================================
echo -e "${YELLOW}>>> [2/4] 下载最新版 RustDesk Server...${PLAIN}"

# 清理旧文件
rm -rf ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}
cd ${INSTALL_DIR}

# 获取最新版本下载链接 (Linux x86_64)
# 注意：这里使用 GitHub API 获取最新 release
LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest | grep "browser_download_url" | grep "x86_64" | cut -d '"' -f 4)

if [[ -z "${LATEST_URL}" ]]; then
    echo -e "${RED}无法获取最新版本链接，请检查网络或 GitHub API 限制。${PLAIN}"
    exit 1
fi

echo "正在下载: ${LATEST_URL}"
wget -O rustdesk-server.zip "${LATEST_URL}"
unzip rustdesk-server.zip
mv amd64/* .
rm -rf amd64 rustdesk-server.zip
chmod +x hbbs hbbr

# ==================================================
# 3. 配置 Systemd 服务
# ==================================================
echo -e "${YELLOW}>>> [3/4] 配置 Systemd 服务...${PLAIN}"

# --- HBBS (ID Server) Service ---
# 注意：-r 指定中继服务器地址，-k _ 强制开启 Key 验证
cat > /etc/systemd/system/rustdesk-hbbs.service <<EOF
[Unit]
Description=RustDesk ID Server (hbbs)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/hbbs -r ${SERVER_IP}:21117 -k _
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# --- HBBR (Relay Server) Service ---
cat > /etc/systemd/system/rustdesk-hbbr.service <<EOF
[Unit]
Description=RustDesk Relay Server (hbbr)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/hbbr -k _
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 重载并启动
systemctl daemon-reload
systemctl enable rustdesk-hbbs rustdesk-hbbr
systemctl start rustdesk-hbbs rustdesk-hbbr

# 等待几秒让 Key 生成
sleep 3

# ==================================================
# 4. 配置防火墙 & 获取 Key
# ==================================================
echo -e "${YELLOW}>>> [4/4] 配置防火墙 & 读取密钥...${PLAIN}"

# 获取公钥
PUB_KEY=$(cat ${INSTALL_DIR}/id_ed25519.pub)

# 配置 UFW (如果已启用)
if command -v ufw > /dev/null; then
    ufw allow 21115:21119/tcp
    ufw allow 21116/udp
    echo -e "${GREEN}已通过 UFW 放行 21115-21119 端口${PLAIN}"
fi

# ==================================================
# 结束输出
# ==================================================
clear
echo "------------------------------------------------"
echo "   RustDesk Server 安装完成 (Debian 12)        "
echo "------------------------------------------------"
echo -e "ID 服务器 (hbbs):     ${GREEN}${SERVER_IP}${PLAIN}"
echo -e "中继服务器 (hbbr):    ${GREEN}${SERVER_IP}${PLAIN}"
echo -e "Key (公钥):           ${GREEN}${PUB_KEY}${PLAIN}"
echo "------------------------------------------------"
echo -e "服务状态检查: systemctl status rustdesk-hbbs"
echo -e "手动查看 Key: cat /opt/rustdesk/id_ed25519.pub"
echo "------------------------------------------------"
echo -e "⚠️  重要提示："
echo -e "1. 如果是云服务器(阿里云/腾讯云/AWS)，请务必在【安全组】放行以下端口："
echo -e "   - TCP: 21115, 21116, 21117, 21118, 21119"
echo -e "   - UDP: 21116"
echo -e "2. 客户端填写 Key 后，连接会加密，更安全。"
echo "------------------------------------------------"
