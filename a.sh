#!/bin/bash

# 获取当前目录的绝对路径
current_dir=$(pwd)

# 获取当前目录的名称
dir_name=$(basename $current_dir)

# 询问用户输入 Django 项目名称
read -p "请输入您的 Django 项目名称: " django_project

# 询问用户输入虚拟环境的最后一部分
read -p "请输入虚拟环境的最后一部分: " virtualenv_name

# 构建 uwsgi.ini 文件的内容
uwsgi_config="[uwsgi]
chdir = $current_dir
module = ${django_project}.wsgi
master = true
processes = 3
threads = 2
socket = /var/run/${dir_name}.sock
vacuum = true
die-on-term = true

chown-socket = www-data:www-data
chmod-socket = 666
uid = www-data
gid = www-data
;这是虚拟路径
virtualenv = $current_dir/$virtualenv_name
"

# 将内容写入 conf/uwsgi.ini 文件
mkdir -p conf
echo "$uwsgi_config" > conf/uwsgi.ini

echo -e "\033[32muwsgi 配置文件已保存到 conf/uwsgi.ini\033[0m"

# 询问用户输入域名
read -p "请输入您的域名（不包括www）: " domain_name

# 构建 Nginx 配置文件的内容
nginx_config="server {
    server_name $domain_name www.$domain_name;
    listen 80;
    listen [::]:80;
    location / {
        include uwsgi_params;
        uwsgi_connect_timeout 30;
        uwsgi_pass unix:/var/run/${dir_name}.sock;
    }
    location /static/ {
        alias $current_dir/static/;
        expires 4h;
    }
    location /media/ {
        alias $current_dir/media/;
    }
    location /robots.txt {
        alias $current_dir/static/root/robots.txt;
    }
    location /sitemap.xml {
        alias $current_dir/static/root/sitemap.xml;
    }
    location /ads.txt {
        alias $current_dir/static/root/ads.txt;
    }
}"

# 定义 Nginx 配置文件的路径，使用当前目录名称作为文件名
nginx_config_file="/etc/nginx/sites-enabled/${dir_name}.conf"

# 使用 sudo 权限将配置内容写入文件
echo "$nginx_config" | sudo tee $nginx_config_file > /dev/null

# 重启 Nginx
sudo systemctl restart nginx

echo -e "\033[32mNginx 配置文件已保存到 $nginx_config_file，并且 Nginx 已重启。\033[0m"


# 创建 log 目录
mkdir -p log

# 构建 Supervisor 配置文件的内容
# 使用当前目录名称作为程序名称
program_name=${dir_name}

# 构建 Supervisor 配置文件的内容
supervisor_config="[program:${program_name}]
command=${current_dir}/env/bin/uwsgi --ini ${current_dir}/conf/uwsgi.ini
directory=${current_dir}
stdout_logfile=${current_dir}/log/stdout.log
stderr_logfile=${current_dir}/log/error.log

process_name=%(program_name)s
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
echo "$supervisor_config" | sudo tee $supervisor_config_file > /dev/null

echo -e "\033[32mSupervisor 配置文件已保存到 $supervisor_config_file\033[0m"

# 重新加载 Supervisor 配置
echo -e "\033[32m重新加载supervisor配置文件\033[0m"
sudo supervisorctl reread
sudo supervisorctl update
echo -e "\033[32msupervisor配置文件加载完成\033[0m"