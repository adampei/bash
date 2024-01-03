#!/bin/bash

# 初始化变量
project_path=""

# 循环遍历所有参数
while [[ $# -gt 0 ]]; do
    case $1 in
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

# 检查是否提供了必需的参数
if [ -z "$project_path" ]; then
    echo "缺少必需的参数。"
    echo "用法: $0 --path <项目路径>"
    exit 1
fi

# 从提供的路径中获取项目名称
dir_name=$(basename "$project_path")

# 定义 Nginx 和 Supervisor 配置文件的路径
nginx_config_file="/etc/nginx/sites-enabled/${dir_name}.conf"
supervisor_config_file="/etc/supervisor/conf.d/${dir_name}.conf"

# 删除 Nginx 配置文件
if [ -f "$nginx_config_file" ]; then
    sudo rm "$nginx_config_file"
    echo "Nginx 配置文件 ${nginx_config_file} 已删除。"
    sudo systemctl reload nginx
else
    echo "Nginx 配置文件 ${nginx_config_file} 不存在。"
fi

# 删除 Supervisor 配置文件
if [ -f "$supervisor_config_file" ]; then
    sudo rm "$supervisor_config_file"
    echo "Supervisor 配置文件 ${supervisor_config_file} 已删除。"
    sudo supervisorctl reread
    sudo supervisorctl update
else
    echo "Supervisor 配置文件 ${supervisor_config_file} 不存在。"
fi
