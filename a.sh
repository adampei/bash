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

echo "配置文件已保存到 conf/uwsgi.ini"