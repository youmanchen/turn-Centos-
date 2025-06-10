#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户"
    exit 1
fi

# 设置变量
COTURN_VERSION="4.6.2"
CONFIG_FILE="/usr/local/etc/turnserver.conf"
LOG_FILE="/var/log/turnserver.log"
SYSTEMD_FILE="/etc/systemd/system/coturn.service"

# 获取用户输入
read -p "请输入服务器的公网 IP 地址: " PUBLIC_IP
read -p "请输入 TURN 服务器的域名（留空则不配置域名）: " DOMAIN
read -p "请输入 TURN 用户名（默认: turnuser）: " TURN_USER
TURN_USER=${TURN_USER:-turnuser}
read -p "请输入 TURN 密码（默认: turnpassword）: " TURN_PASSWORD
TURN_PASSWORD=${TURN_PASSWORD:-turnpassword}

# 更新系统并安装依赖
echo "正在更新系统并安装依赖..."
yum update -y
yum install -y epel-release
yum install -y gcc make libevent libevent-devel openssl-devel wget tar

# 下载并安装 Coturn
echo "正在下载并安装 Coturn ${COTURN_VERSION}..."
wget https://github.com/coturn/coturn/archive/refs/tags/${COTURN_VERSION}.tar.gz
tar -zxvf ${COTURN_VERSION}.tar.gz
cd coturn-${COTURN_VERSION}
./configure
make
make install
cd ..
rm -rf coturn-${COTURN_VERSION} ${COTURN_VERSION}.tar.gz

# 创建配置文件
echo "正在创建 Coturn 配置文件..."
cat > ${CONFIG_FILE} << EOF
listening-ip=0.0.0.0
listening-port=3478
external-ip=${PUBLIC_IP}
server-name=${DOMAIN}
user=${TURN_USER}:${TURN_PASSWORD}
realm=${DOMAIN:-turnserver}
lt-cred-mech
log-file=${LOG_FILE}
verbose
EOF

# 设置文件权限
chmod 644 ${CONFIG_FILE}
touch ${LOG_FILE}
chmod 664 ${LOG_FILE}

# 配置防火墙
echo "正在配置防火墙..."
firewall-cmd --permanent --add-port=3478/tcp
firewall-cmd --permanent --add-port=3478/udp
firewall-cmd --permanent --add-port=5349/tcp
firewall-cmd --permanent --add-port=5349/udp
firewall-cmd --reload

# 创建 systemd 服务
echo "正在创建 systemd 服务..."
cat > ${SYSTEMD_FILE} << EOF
[Unit]
Description=Coturn TURN Server
After=network.target

[Service]
ExecStart=/usr/local/bin/turnserver -c ${CONFIG_FILE}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable coturn
systemctl start coturn

# 检查服务状态
if systemctl is-active --quiet coturn; then
    echo "Coturn 服务已成功启动！"
else
    echo "Coturn 服务启动失败，请检查日志：${LOG_FILE}"
    exit 1
fi

# 输出配置信息
echo -e "\n安装完成！以下是你的 TURN 服务器配置："
echo "TURN 服务器地址: turn:${PUBLIC_IP}:3478"
if [ ! -z "$DOMAIN" ]; then
    echo "TURN 域名: turn:${DOMAIN}:3478"
fi
echo "用户名: ${TURN_USER}"
echo "密码: ${TURN_PASSWORD}"
echo "日志文件: ${LOG_FILE}"
echo -e "\n请使用 WebRTC 客户端或工具（如 trickle-ice）测试连接。"
echo "如需 TLS 支持，请手动配置 SSL 证书并更新 ${CONFIG_FILE}。"
