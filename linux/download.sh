#!/bin/bash

# 函数：显示使用方法
show_usage() {
    echo "使用方法: $0 <下载链接> [文件名] <认证头> <下载目录>"
    echo "示例: $0 'https://example.com/model.safetensors' 'custom_name.safetensors' 'Authorization: Bearer xxx' '/path/to/download'"
}

# 检查参数数量
if [ "$#" -lt 3 ]; then
    echo "❌ 参数不足"
    show_usage
    exit 1
fi

# 解析参数
URL="$1"
HEADER="$3"
DOWNLOAD_DIR="$4"

# 如果没有提供文件名，从URL中提取
if [ "$#" -eq 3 ]; then
    # 从URL中提取文件名，先去除查询参数，再获取最后一个路径部分
    FILENAME=$(echo "$URL" | sed 's/[?].*$//' | awk -F'/' '{print $NF}')
    HEADER="$2"
    DOWNLOAD_DIR="$3"
else
    FILENAME="$2"
fi

echo "解析参数，下载地址：URL: $URL, 文件名：$FILENAME, 认证头：$HEADER, 下载目录：$DOWNLOAD_DIR"


# 检查下载目录是否存在，不存在则创建
if [ ! -d "$DOWNLOAD_DIR" ]; then
    echo "📁 创建下载目录: $DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"
fi

# 完整的下载路径
FULL_PATH="$DOWNLOAD_DIR/$FILENAME"

echo "🚀 开始下载..."
echo "📥 下载链接: $URL"
echo "📂 保存为: $FULL_PATH"

# 检查文件是否已存在
if [ -f "$FULL_PATH" ]; then
    echo "⚠️ 文件已存在，跳过下载: $FULL_PATH"
    exit 0
fi

# 使用aria2c下载
if aria2c -o "$FILENAME" \
         -d "$DOWNLOAD_DIR" \
         -x 16 \
         -s 16 \
         --header="$HEADER" \
         "$URL"; then
    echo "✅ 下载完成: $FULL_PATH"
else
    echo "❌ 下载失败"
    exit 1
fi