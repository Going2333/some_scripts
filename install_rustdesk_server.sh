#!/bin/bash
set -e  # 遇到错误立即退出

# 定义颜色输出（增强可读性）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 重置颜色

# 1. 检查并安装 Docker
echo -e "${YELLOW}=== 检查 Docker 环境 ===${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker 未安装，开始自动安装...${NC}"
    # 更新软件源
    apt update -y
    # 安装依赖
    apt install -y ca-certificates curl gnupg lsb-release
    # 添加 Docker GPG 密钥
    mkdir -p /etc/apt/trusted.gpg.d
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
    # 添加 Docker 软件源
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    # 安装 Docker
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    # 启动并开机自启 Docker
    systemctl enable --now docker
    echo -e "${GREEN}Docker 安装完成！${NC}"
else
    echo -e "${GREEN}Docker 已安装，跳过安装步骤${NC}"
fi

# 2. 创建 RustDesk 数据目录（确保数据持久化）
echo -e "\n${YELLOW}=== 创建数据目录 ===${NC}"
RUSTDESK_DIR="/opt/rustdesk-server"
mkdir -p ${RUSTDESK_DIR}/data
chmod -R 755 ${RUSTDESK_DIR}
echo -e "${GREEN}数据目录已创建：${RUSTDESK_DIR}${NC}"

# 3. 停止并删除旧的 RustDesk 容器（避免端口冲突）
echo -e "\n${YELLOW}=== 清理旧容器（如果存在） ===${NC}"
docker stop rustdesk-hbbs rustdesk-hbbr &> /dev/null || true
docker rm rustdesk-hbbs rustdesk-hbbr &> /dev/null || true
echo -e "${GREEN}旧容器清理完成${NC}"

# 4. 启动 RustDesk 服务端容器
echo -e "\n${YELLOW}=== 启动 RustDesk 服务端 ===${NC}"
# 获取服务器公网/内网 IP（优先公网）
SERVER_IP=$(curl -s icanhazip.com || hostname -I | awk '{print $1}')

# 启动 hbbs（ID 注册/中继服务器）
docker run -d \
  --name rustdesk-hbbs \
  --restart always \
  -p 21115:21115 \
  -p 21116:21116/tcp \
  -p 21116:21116/udp \
  -p 21118:21118 \
  -v ${RUSTDESK_DIR}/data:/root \
  rustdesk/rustdesk-server:latest \
  hbbs -r ${SERVER_IP}:21117

# 启动 hbbr（中继服务器）
docker run -d \
  --name rustdesk-hbbr \
  --restart always \
  -p 21117:21117 \
  -p 21119:21119 \
  -v ${RUSTDESK_DIR}/data:/root \
  rustdesk/rustdesk-server:latest \
  hbbr

# 5. 验证启动状态
echo -e "\n${YELLOW}=== 验证服务状态 ===${NC}"
sleep 3  # 等待容器启动
if docker ps | grep -q "rustdesk-hbbs"; then
    echo -e "${GREEN}hbbs 服务启动成功！${NC}"
else
    echo -e "${RED}hbbs 服务启动失败！${NC}"
    exit 1
fi

if docker ps | grep -q "rustdesk-hbbr"; then
    echo -e "${GREEN}hbbr 服务启动成功！${NC}"
else
    echo -e "${RED}hbbr 服务启动失败！${NC}"
    exit 1
fi

# 6. 输出配置信息
echo -e "\n${GREEN}=== RustDesk 服务端部署完成！ ===${NC}"
echo -e "服务器 IP：${SERVER_IP}"
echo -e "hbbs 端口：21115/21116(tcp/udp)/21118"
echo -e "hbbr 端口：21117/21119"
echo -e "\n${YELLOW}客户端配置说明：${NC}"
echo -e "1. 打开 RustDesk 客户端，点击左上角「菜单」→「ID/中继服务器」"
echo -e "2. ID 服务器：${SERVER_IP}"
echo -e "3. 中继服务器：${SERVER_IP}"
echo -e "4. API 服务器：留空"
echo -e "5. 密钥：可在 ${RUSTDESK_DIR}/data/id_ed25519.pub 文件中查看"
echo -e "\n查看日志命令："
echo -e "  docker logs -f rustdesk-hbbs"
echo -e "  docker logs -f rustdesk-hbbr"
echo -e "\n停止服务命令："
echo -e "  docker stop rustdesk-hbbs rustdesk-hbbr"
echo -e "\n启动服务命令："
echo -e "  docker start rustdesk-hbbs rustdesk-hbbr"
