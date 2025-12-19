#!/bin/bash

# ==================================================
# NexusPHP (xiaomlove版) Docker 一键安装脚本
# Author: Gemini
# Description: 自动配置 MySQL + NexusPHP 并适配 IP 访问
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误：未检测到 Docker，请先安装！${PLAIN}"
    exit 1
fi

clear
echo "------------------------------------------------"
echo "   NexusPHP (xiaomlove) 自动安装脚本            "
echo "------------------------------------------------"

# ==================================================
# 1. 收集配置信息
# ==================================================
echo -e "${YELLOW}>> [1/4] 配置站点信息：${PLAIN}"

# IP
DEFAULT_IP=$(curl -s -4 ifconfig.me)
read -p "请输入站点 IP (默认: ${DEFAULT_IP}): " USER_IP
[[ -z "${USER_IP}" ]] && USER_IP="${DEFAULT_IP}"

# 端口
read -p "请输入 Web 端口 (默认: 80): " USER_PORT
[[ -z "${USER_PORT}" ]] && USER_PORT="80"

# 数据库密码
GEN_PASS=$(date +%s | sha256sum | base64 | head -c 12)
read -p "设置数据库密码 (回车随机: ${GEN_PASS}): " DB_PASS
[[ -z "${DB_PASS}" ]] && DB_PASS="${GEN_PASS}"

# 处理 DOMAIN 变量
# 如果端口不是80，NexusPHP 通常需要 "IP:端口" 格式作为 Domain
if [[ "$USER_PORT" == "80" ]]; then
    SITE_DOMAIN="${USER_IP}"
else
    SITE_DOMAIN="${USER_IP}:${USER_PORT}"
fi

echo -e "\n${GREEN}配置确认：${PLAIN}"
echo -e "访问地址: http://${SITE_DOMAIN}"
echo -e "数据库密码: ${DB_PASS}"
echo -e "------------------------------------------------"
read -n 1 -s -r -p "按任意键开始安装..."
echo ""

# ==================================================
# 2. 准备目录
# ==================================================
INSTALL_DIR="/opt/nexusphp_new"
mkdir -p "$INSTALL_DIR/mysql"
mkdir -p "$INSTALL_DIR/attachments"
cd "$INSTALL_DIR"

echo -e "${YELLOW}>> [2/4] 生成 docker-compose.yml...${PLAIN}"

# 生成 Docker Compose 文件
# xiaomlove 镜像通常内置了环境，但我们需要独立的 MySQL 以保证数据安全
cat > docker-compose.yml <<EOF
version: '3'
services:
  db:
    image: mysql:5.7
    container_name: nexusphp_db
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASS}
      MYSQL_DATABASE: nexusphp
      MYSQL_USER: nexusphp
      MYSQL_PASSWORD: ${DB_PASS}
    volumes:
      - ./mysql:/var/lib/mysql
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    restart: always

  web:
    image: xiaomlove/nexusphp:latest
    container_name: nexusphp_web
    ports:
      - "${USER_PORT}:80"
    environment:
      - DOMAIN=${SITE_DOMAIN}
      - DB_HOST=db
      - DB_PORT=3306
      - DB_DATABASE=nexusphp
      - DB_USERNAME=root
      - DB_PASSWORD=${DB_PASS}
    volumes:
      # 映射附件目录，防止重启容器后种子封面丢失
      - ./attachments:/var/www/html/attachments
    depends_on:
      - db
    restart: always
EOF

# ==================================================
# 3. 启动服务
# ==================================================
echo -e "${YELLOW}>> [3/4] 启动容器...${PLAIN}"

# 尝试使用 docker compose (新版) 或 docker-compose (旧版)
if docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}启动失败！请检查端口是否被占用。${PLAIN}"
    exit 1
fi

# ==================================================
# 4. 等待初始化
# ==================================================
echo -e "${YELLOW}>> [4/4] 等待数据库自动初始化 (约30秒)...${PLAIN}"
echo -e "xiaomlove 镜像会在首次启动时自动导入数据库，请勿中断。"

# 倒计时进度条
for i in {30..1}; do
    echo -ne "剩余时间: $i 秒 \r"
    sleep 1
done

# 修复权限 (防止上传附件失败)
docker exec -u root nexusphp_web chown -R www-data:www-data /var/www/html/attachments
docker exec -u root nexusphp_web chmod -R 777 /var/www/html/attachments

echo -e "\n------------------------------------------------"
echo -e "${GREEN}🎉 安装完成！${PLAIN}"
echo "------------------------------------------------"
echo -e "访问地址:     http://${SITE_DOMAIN}"
echo -e "数据库密码:   ${DB_PASS}"
echo -e "安装目录:     ${INSTALL_DIR}"
echo "------------------------------------------------"
echo -e "⚠️  默认管理员账号："
echo -e "用户名: ${GREEN}admin${PLAIN}"
echo -e "密码:   ${GREEN}admin123${PLAIN} (如果不对，尝试 admin/admin)"
echo -e "请立即登录并修改密码！"
echo "------------------------------------------------"
