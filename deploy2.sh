#!/bin/bash

# 初始化变量
domain_name=""
project_path=""
project_name=""

# 解析命令行参数
while getopts ":d:p:n:" opt; do
  case $opt in
    d) domain_name="$OPTARG" ;;
    p) project_path="${OPTARG%/}" ;;
    n) project_name="$OPTARG" ;;
    \?) echo "无效的选项 -$OPTARG" >&2; exit 1 ;;
    :) echo "选项 -$OPTARG 需要参数." >&2; exit 1 ;;
  esac
done

# 检查必需参数
if [ -z "$domain_name" ] || [ -z "$project_path" ] || [ -z "$project_name" ]; then
    echo "缺少必需的参数。用法: $0 -d <域名> -p <项目路径> -n <项目名称>"
    exit 1
fi

# 更新和安装软件包
echo "正在更新软件包列表并安装必需的软件..."
sudo apt-get update && sudo apt-get install -y nginx supervisor python3-venv build-essential python3-dev

# 设置项目变量
log_dir="$project_path/log"
socket_path="/var/run/$project_name.sock"

# 创建日志目录
mkdir -p "$log_dir"

# 获取系统信息
cpu_cores=$(nproc)
gunicorn_workers=$((2 * cpu_cores + 1))

# 配置 Gunicorn
gunicorn_config="import multiprocessing

bind = 'unix:$socket_path'
workers = $gunicorn_workers
worker_class = 'gevent'
worker_connections = 1000
timeout = 30
keepalive = 2

errorlog = '${log_dir}/gunicorn_error.log'
accesslog = '${log_dir}/gunicorn_access.log'
loglevel = 'info'

proc_name = '${project_name}_gunicorn'

# 设置用户和组
user = 'www-data'
group = 'www-data'

# 设置 umask 以确保正确的文件权限
umask = 0o002
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
        proxy_pass http://unix:$socket_path;
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

nginx_config_file="/etc/nginx/sites-enabled/${project_name}.conf"
echo "$nginx_config" | sudo tee "$nginx_config_file" > /dev/null
sudo systemctl restart nginx
echo "Nginx 配置文件已保存并重启服务"

# Supervisor 配置
supervisor_config="[program:${project_name}]
command=${project_path}/env/bin/gunicorn ${project_name}.wsgi:application -c ${project_path}/conf/gunicorn.py
directory=${project_path}
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=${log_dir}/gunicorn_supervisor.log
"

supervisor_config_file="/etc/supervisor/conf.d/${project_name}.conf"
echo "$supervisor_config" | sudo tee "$supervisor_config_file" > /dev/null
echo "Supervisor 配置文件已保存"

# Celery 配置（如果需要）
if [ -f "$project_path/run_celery.sh" ]; then
    echo "配置 Celery..."
    sudo apt-get install -y redis-server
    sudo systemctl enable --now redis-server

    celery_supervisor_config="
[program:${project_name}_celery]
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
logrotate_config="/var/log/${project_name}/*.log {
    weekly
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0660 www-data www-data
    sharedscripts
    postrotate
        if [ -f /var/run/supervisor.sock ]; then
            supervisorctl signal HUP ${project_name}:*
        fi
    endscript
}"

echo "$logrotate_config" | sudo tee "/etc/logrotate.d/$project_name" > /dev/null
sudo logrotate -d "/etc/logrotate.d/$project_name"

# 设置项目目录的权限
echo "设置项目目录权限..."
sudo chown -R www-data:www-data "$project_path"
sudo chmod -R 775 "$project_path"

# 确保 socket 文件目录存在并具有正确的权限
sudo mkdir -p /var/run
sudo chown root:www-data /var/run
sudo chmod 775 /var/run

# 重新加载 Supervisor 配置
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all

echo "部署完成！请检查服务是否正常运行。"

# 显示一些有用的命令
echo "
一些有用的命令：
查看 Gunicorn 错误日志: sudo tail -f ${log_dir}/gunicorn_error.log
查看 Supervisor 日志: sudo tail -f ${log_dir}/gunicorn_supervisor.log
重启 Gunicorn: sudo supervisorctl restart ${project_name}
重启 Nginx: sudo systemctl restart nginx
"