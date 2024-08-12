#!/bin/bash

# 初始化变量
domain_name=""
project_path=""

# 解析命令行参数
while getopts ":d:p:" opt; do
  case $opt in
    d) domain_name="$OPTARG" ;;
    p) project_path="${OPTARG%/}" ;;
    \?) echo "无效的选项 -$OPTARG" >&2; exit 1 ;;
    :) echo "选项 -$OPTARG 需要参数." >&2; exit 1 ;;
  esac
done

# 检查必需参数
if [ -z "$domain_name" ] || [ -z "$project_path" ]; then
    echo "缺少必需的参数。用法: $0 -d <域名> -p <项目路径>"
    exit 1
fi

# 更新和安装软件包
echo "正在更新软件包列表并安装必需的软件..."
sudo apt-get update && sudo apt-get install -y nginx supervisor python3-venv build-essential python3-dev

# 设置项目变量
dir_name=$(basename "$project_path")
log_dir="$project_path/log"

# 创建日志目录
mkdir -p "$log_dir" && sudo chmod -R 777 "$log_dir"
echo "日志目录已创建并设置权限: $log_dir"

# 获取系统信息
cpu_cores=$(nproc)
total_mem=$(free -m | awk '/^Mem:/{print $2}')

# 配置 Gunicorn
gunicorn_workers=$((2 * cpu_cores + 1))
gunicorn_config="import multiprocessing

bind = 'unix:/var/run/${dir_name}.sock'
workers = $gunicorn_workers
worker_class = 'gevent'
worker_connections = 1000
timeout = 30
keepalive = 2

errorlog = '${log_dir}/gunicorn_error.log'
accesslog = '${log_dir}/gunicorn_access.log'
loglevel = 'info'

proc_name = '${dir_name}_gunicorn'
"

mkdir -p "$project_path/conf"
echo "$gunicorn_config" > "$project_path/conf/gunicorn.py"
echo "Gunicorn 配置文件已保存到 $project_path/conf/gunicorn.py"

# Nginx 配置
nginx_config="server {
    server_name $domain_name www.$domain_name;
    listen 80;
    listen [::]:80;
    client_max_body_size 100M;

    location / {
        proxy_pass http://unix:/var/run/${dir_name}.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /static/ {
        alias $project_path/static/;
        expires 4h;
    }

    location /media/ {
        alias $project_path/media/;
    }

    location ~ ^/(robots\.txt|sitemap\.xml|ads\.txt)$ {
        root $project_path/static/root;
    }
}"

nginx_config_file="/etc/nginx/sites-enabled/${dir_name}.conf"
echo "$nginx_config" | sudo tee "$nginx_config_file" > /dev/null
sudo systemctl restart nginx
echo "Nginx 配置文件已保存并重启服务"

# Supervisor 配置
supervisor_config="[program:${dir_name}]
command=${project_path}/env/bin/gunicorn ${dir_name}.wsgi:application -c ${project_path}/conf/gunicorn.py
directory=${project_path}
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=${log_dir}/gunicorn_supervisor.log
"

supervisor_config_file="/etc/supervisor/conf.d/${dir_name}.conf"
echo "$supervisor_config" | sudo tee "$supervisor_config_file" > /dev/null
echo "Supervisor 配置文件已保存"

# Celery 配置（如果需要）
if [ -f "$project_path/run_celery.sh" ]; then
    echo "配置 Celery..."
    sudo apt-get install -y redis-server
    sudo systemctl enable --now redis-server

    celery_supervisor_config="
[program:${dir_name}_celery]
command=bash $project_path/run_celery.sh
directory=$project_path
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=$log_dir/celery.log
stderr_logfile=$log_dir/celery_error.log
"
    echo "$celery_supervisor_config" | sudo tee -a "$supervisor_config_file" > /dev/null
    echo "Celery 配置已添加"
fi

# 日志轮换配置
logrotate_config="/var/log/${dir_name}/*.log {
    weekly
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data www-data
    sharedscripts
    postrotate
        if [ -f /var/run/supervisor.sock ]; then
            supervisorctl signal HUP ${dir_name}:*
        fi
    endscript
}"

echo "$logrotate_config" | sudo tee "/etc/logrotate.d/$dir_name" > /dev/null
sudo logrotate -d "/etc/logrotate.d/$dir_name"

# 重新加载 Supervisor 配置
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all

echo "部署完成！"