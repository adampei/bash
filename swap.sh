#!/bin/bash

# 函数：显示用法
usage() {
    echo "Usage: $0 -s SIZE"
    echo "  -s, --size SIZE    设置交换分区大小（MB）"
    exit 1
}

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要以 root 权限运行"
    exit 1
fi

# 解析参数
SIZE=0
while [ "$1" != "" ]; do
    case $1 in
        -s | --size )
            shift
            SIZE=$1
            ;;
        * )
            usage
            ;;
    esac
    shift
done

# 检查大小参数是否被提供
if [ "$SIZE" -eq 0 ]; then
    echo "错误：未指定交换分区大小"
    usage
fi

# 创建交换文件
SWAPFILE="/swapfile"
echo "创建大小为 $SIZE MB 的交换文件..."
dd if=/dev/zero of=$SWAPFILE bs=1M count="$SIZE" status=progress

# 设置交换文件权限
echo "设置交换文件权限..."
chmod 600 $SWAPFILE

# 设置交换空间
echo "设置交换空间..."
mkswap $SWAPFILE

# 启用交换空间
echo "启用交换空间..."
swapon $SWAPFILE

# 显示交换空间信息
echo "交换空间设置完成。"
swapon -s
