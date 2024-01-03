#!/bin/bash

# 更新软件包列表
echo "正在更新软件包列表..."
sudo apt-get update

# 检查是否安装了 pip3，如果没有则安装
if ! command -v pip3 &> /dev/null
then
    echo "pip3 未安装，正在安装..."
    sudo apt-get install -y python3-pip
else
    echo "pip3 已安装。"
fi

# 安装 Supervisor
echo "正在安装 Supervisor..."
sudo pip3 install supervisor

# 检查 Supervisor 是否正在运行并停止它
if sudo systemctl is-active --quiet supervisord; then
    echo "Supervisor 正在运行，正在停止..."
    sudo systemctl stop supervisord
fi

# 创建 Supervisor systemd 服务文件
echo "创建 Supervisor systemd 服务文件..."
cat <<EOF | sudo tee /etc/systemd/system/supervisord.service
[Unit]
Description=Supervisor daemon

[Service]
Type=forking
ExecStart=/usr/local/bin/supervisord -c /etc/supervisor/supervisord.conf
ExecReload=/usr/local/bin/supervisorctl reload
ExecStop=/usr/local/bin/supervisorctl shutdown
User=root
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动 Supervisor 服务
echo "启用并启动 Supervisor 服务..."
sudo systemctl enable supervisord
sudo systemctl start supervisord

# 显示服务状态
echo "显示 Supervisor 服务状态..."
sudo systemctl status supervisord
