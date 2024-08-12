#!/bin/bash

# 获取远程更新
git fetch origin

# 重置本地分支到远程分支的状态
git reset --hard origin/main

# 清理未跟踪的文件和目录
git clean -fd
