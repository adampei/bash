#!/bin/bash

# 初始化文件路径变量
FILE_PATH=""

# 使用getopts解析命令行参数
while getopts p:h flag; do
    # shellcheck disable=SC2220
    case "${flag}" in
    p) FILE_PATH=${OPTARG} ;;
    h)
        echo -e "\033[32mUsage: $0 -p /path/to/your/file\033[0m"
        exit 0
        ;;
    esac
done

# 检查是否已经输入了文件路径
if [ -z "$FILE_PATH" ]; then
    echo -e "\033[31mError: Please specify a file path with the -p option.\033[0m"
    echo -e "\033[32mUsage: $0 -p /path/to/your/file\033[0m"
    exit 1
fi

# 使用dialog创建一个菜单，让用户选择一个服务器
SERVER_NAME=$(
    dialog --clear \
        --backtitle "Choose a server" \
        --title "Choose a server" \
        --menu "Choose one of the following options:"
    # 高度, 宽度, 菜单数量
    15 100 3 \
        "hz" "speech,sheetrules" \
        "netcup" "imagetotext" \
        "server3" "文本3" \
        2>&1 >/dev/tty
)

clear

# 根据服务器名设置服务器IP地址
case "$SERVER_NAME" in
"hz") SERVER_IP="5.78.70.195" ;;
"netcup") SERVER_IP="94.16.105.140" ;;
"server3") SERVER_IP="5.78.70.197" ;;
*)
    echo -e "\033[31mError: Unknown server name.\033[0m"
    exit 1
    ;;
esac

# 使用scp命令将文件复制到远程服务器
scp $FILE_PATH root@$SERVER_IP:/home/