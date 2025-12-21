#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

echo "============================================"
echo "    Vaultwarden + Caddy 灵活端口版"
echo "============================================"

# --- 交互输入环节 ---
read -p "请输入你的域名: " DOMAIN
read -p "请输入你希望 Caddy 使用的 HTTPS 端口 [默认 443]: " HTTPS_PORT
HTTPS_PORT=${HTTPS_PORT:-443}

read -p "请输入 SSL 证书 (.crt/.pem) 绝对路径: " CERT_PATH
read -p "请输入 SSL 私钥 (.key) 绝对路径: " KEY_PATH
read -p "请输入管理后台 Admin Token (强密码): " ADMIN_TOKEN
read -p "请输入数据存放目录 [默认 /www/wwwroot/demo/]: " DATA_DIR
DATA_DIR=${DATA_DIR:-/www/wwwroot/demo/}

# --- 1. 环境检查与安装 ---
if ! command -v docker &> /dev/null; then
    echo "正在安装 Docker..."
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable --now docker
fi

if ! command -v caddy &> /dev/null; then
    echo "正在安装 Caddy..."
    apt-get update && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update && apt-get install -y caddy
fi

# --- 2. 部署 Vaultwarden ---
echo "--- 正在启动 Vaultwarden 容器 ---"
docker stop bitwardenrs 2>/dev/null || true
docker rm bitwardenrs 2>/dev/null || true

# 默认关闭注册 (SIGNUPS_ALLOWED=false)
docker run -d --name bitwardenrs \
  --restart unless-stopped \
  -e WEBSOCKET_ENABLED=true \
  -e SIGNUPS_ALLOWED=false \
  -e ADMIN_TOKEN="${ADMIN_TOKEN}" \
  -v "${DATA_DIR}:/data/" \
  -p 127.0.0.1:6666:80 \
  -p 127.0.0.1:3012:3012 \
  vaultwarden/server:latest

# --- 3. 配置 Caddy ---
echo "--- 正在配置 Caddy (使用端口 ${HTTPS_PORT}) ---"
# Caddyfile 指定端口的格式是域名后面加冒号
cat <<EOF > /etc/caddy/Caddyfile
${DOMAIN}:${HTTPS_PORT} {
    tls ${CERT_PATH} ${KEY_PATH}
    encode gzip

    # 代理设置
    reverse_proxy /notifications/hub 127.0.0.1:3012
    reverse_proxy 127.0.0.1:6666

    header {
        Strict-Transport-Security "max-age=31536000;"
    }
}
EOF

# --- 4. 重启并验证 ---
systemctl restart caddy

echo "============================================"
echo "部署完成！"
echo "访问地址: https://${DOMAIN}:${HTTPS_PORT}"
echo "管理后台: https://${DOMAIN}:${HTTPS_PORT}/admin"
echo "管理密码: ${ADMIN_TOKEN}"
echo "注册状态: 已默认关闭"
echo "============================================"
