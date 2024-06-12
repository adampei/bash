#!/bin/bash

# 初始化变量
domain_name=""
project_path=""

# 循环遍历所有参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain|-d)
            domain_name="$2"
            shift # 移过参数值
            shift # 移过参数名
            ;;
        --path|-p)
            project_path="$2"
            shift # 移过参数值
            shift # 移过参数名
            ;;
        *)
            shift # 移过未知参数
            ;;
    esac
done

# 检查 project_path 是否以反斜线结尾，并去除它
if [[ "$project_path" == */ ]]; then
    project_path="${project_path%/}"
fi

# 检查是否所有必需的参数都被设置
if [ -z "$domain_name" ] || [ -z "$project_path" ]; then
    echo "缺少必需的参数。"
    echo "用法: $0 --domain <域名> --path <项目路径>"
    exit 1
fi


# 更新软件包列表并安装必需的软件
echo "正在更新软件包列表并安装必需的软件..."
sudo apt-get update
sudo apt-get install -y nginx supervisor python3-venv build-essential python3-dev


# 从提供的路径中获取项目名称（假设路径的最后一部分是项目名称）
dir_name=$(basename "$project_path")

# 创建日志目录并设置权限
log_dir="$project_path/log"
mkdir -p "$log_dir"
sudo chmod -R 777 "$log_dir"
echo "日志目录已创建并设置权限: $log_dir"

# ---------------------------------------------------------------------------------------------------------
# 获取CPU核心数
cpu_cores=$(nproc)
# 获取系统总内存大小（单位：MB）
total_mem=$(free -m | awk '/^Mem:/{print $2}')
# 计算 reload-on-rss 的值，例如设置为总内存的 25%
# shellcheck disable=SC2004
reload_on_rss=$(($total_mem / 4))
# 构建 uwsgi.ini 文件的内容
# 创建 uwsgi 配置字符串
uwsgi_config="[uwsgi]
strict = true
master = true
enable-threads = true
vacuum = true                        ; Delete sockets during shutdown
single-interpreter = true
die-on-term = true                   ; Shutdown when receiving SIGTERM (default is respawn)
need-app = true

disable-logging = true               ; Disable built-in logging, 禁用内置日志,提高性能
;log-4xx = true                       ; but log 4xx's anyway, 但是仍然记录4xx
;log-5xx = true                       ; and 5xx's, 以及5xx
logto = $log_dir/uwsgi.log
logformat=%(ltime) \"%(method) %(uri) %(proto)\" status=%(status) res-time=%(msecs)ms

harakiri = 60                        ; forcefully kill workers after 60 seconds,
py-call-osafterfork = true           ; allow workers to trap signals

max-requests = 1000                  ; Restart workers after this many requests
max-worker-lifetime = 3600           ; Restart workers after this many seconds
reload-on-rss = $reload_on_rss       ; Restart workers after this much resident memory
worker-reload-mercy = 60             ; How long to wait before forcefully killing workers
socket = /var/run/${dir_name}.sock
chown-socket = www-data:www-data
chmod-socket = 666
uid = www-data
gid = www-data
chdir = $project_path
module = ${dir_name}.wsgi
virtualenv = $project_path/env
env = DEBUG=no


cheaper-algo = busyness
processes = $(($cpu_cores * 2))      ; Maximum number of workers allowed
cheaper = $cpu_cores
cheaper-initial = $cpu_cores         ; Workers created at startup
cheaper-overload = 1                 ; Length of a cycle in seconds
cheaper-step = $cpu_cores            ; How many workers to spawn at a time

cheaper-busyness-multiplier = 30     ; How many cycles to wait before killing workers
cheaper-busyness-min = 20            ; Below this threshold, kill workers (if stable for multiplier cycles)
cheaper-busyness-max = 70            ; Above this threshold, spawn new workers
cheaper-busyness-backlog-alert = 16  ; Spawn emergency workers if more than this many requests are waiting in the queue
cheaper-busyness-backlog-step = 2    ; How many emergency workers to create if there are too many requests in the queue
"

# 将内容写入 conf/uwsgi.ini 文件
mkdir -p "$project_path/conf"
echo "$uwsgi_config" > "$project_path/conf/uwsgi.ini"

echo -e "\033[32muwsgi 配置文件已保存到 $project_path/conf/uwsgi.ini\033[0m"

# ---------------------------------------------------------------------------------------------------------
# 构建 Nginx 配置文件的内容
nginx_config="server {
    server_name $domain_name www.$domain_name;
    listen 80;
    listen [::]:80;
    client_max_body_size 100M;
    location / {
        include uwsgi_params;
        uwsgi_connect_timeout 30;
        uwsgi_pass unix:/var/run/${dir_name}.sock;
    }
    location /static/ {
        alias $project_path/static/;
        expires 4h;
    }
    location /media/ {
        alias $project_path/media/;
    }
    location /robots.txt {
        alias $project_path/static/root/robots.txt;
    }
    location /sitemap.xml {
        alias $project_path/static/root/sitemap.xml;
    }
    location /ads.txt {
        alias $project_path/static/root/ads.txt;
    }
}"

# 定义 Nginx 配置文件的路径，使用项目目录名称作为文件名
nginx_config_file="/etc/nginx/sites-enabled/${dir_name}.conf"

# 使用 sudo 权限将配置内容写入文件
echo "$nginx_config" | sudo tee "$nginx_config_file" > /dev/null

# 重启 Nginx
sudo systemctl restart nginx

echo -e "\033[32mNginx 配置文件已保存到  $nginx_config_file  ,并且 Nginx 已重启。\033[0m"

# ---------------------------------------------------------------------------------------------------------
# 构建 Supervisor 配置文件的内容
supervisor_config="[program:${dir_name}]
command=${project_path}/env/bin/uwsgi --ini ${project_path}/conf/uwsgi.ini
directory=${project_path}
autorestart=true
startsecs=1
stopasgroup=true
killasgroup=true
stopwaitsecs=5
autostart=true
"

# 定义 Supervisor 配置文件的路径
supervisor_config_path="/etc/supervisor/conf.d"
supervisor_config_file="${supervisor_config_path}/${dir_name}.conf"

# 确保目录存在
sudo mkdir -p "$supervisor_config_path"

# 使用 sudo 权限将配置内容写入文件
echo "$supervisor_config" | sudo tee "$supervisor_config_file" > /dev/null

echo -e "\033[32mSupervisor 配置文件已保存到 $supervisor_config_file\033[0m"

# ---------------------------------------------------------------------------------------------------------
# 构建 Celery Supervisor 配置文件的内容
# 检查 run_celery.sh 是否存在
if [ -f "$project_path/run_celery.sh" ]; then
  # 安装 Redis
  echo "正在安装 Redis..."
  sudo apt-get install -y redis-server

  # 启动 Redis 服务
  sudo systemctl start redis-server
  sudo systemctl enable redis-server
  sudo systemctl status redis-server
  echo -e "\033[32mRedis 服务已启动。\033[0m"
#  睡眠2秒
  sleep 2
  echo "正在配置 Celery 进程守护"
    # 构建 Celery Supervisor 配置文件的内容
  celery_supervisor_config="[program:${dir_name}_celery]
command=bash $project_path/run_celery.sh
directory=$project_path
autostart=true
autorestart=true
startsecs=1
stopasgroup=true
killasgroup=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=$log_dir/celery.log
stderr_logfile=$log_dir/celery_error.log
"
    # 写入 Celery Supervisor 配置文件
    echo "$celery_supervisor_config" | sudo tee -a "$supervisor_config_file" > /dev/null

    echo -e "\033[32mCelery Supervisor 配置已添加。\033[0m"
else
    echo -e "\033[33m未找到 run_celery.sh，跳过 Celery 配置。\033[0m"
fi



# 重新加载 Supervisor 配置
sudo supervisorctl reread
sudo supervisorctl update

echo -e "\033[32msupervisor配置文件加载完成\033[0m"
