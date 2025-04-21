#!/bin/bash

# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 导出工具函数
source ./tools.sh

# 函数：显示使用方法
show_usage() {
    echo "使用方法: $0 <下载链接> [文件名] <认证头> <下载目录>"
    echo "示例: $0 'https://example.com/model.safetensors' 'custom_name.safetensors' 'Authorization: Bearer xxx' '/path/to/download'"
}

download_file() {
           # 检查并安装必要的工具
            check_and_install_dependency "yq"
            check_and_install_dependency "jq"
            # 初始化aria2c
            tools_init_aria2c
  # 检查 TOML 文件
  MODELS_TOML="$ROOT_DIR/models.toml"
  if [ ! -f "$MODELS_TOML" ]; then
      echo "❌ 未找到模型配置文件：$MODELS_TOML"
  else
      # 获取 HF_TOKEN
      HF_TOKEN=$(tools_get_hf_token)
      echo "🚀 开始下载模型"
      # 给下载脚本添加执行权限
      cd "$ROOT_DIR" || exit
      chmod +x download.sh


      # 使用 yq 将 TOML 转换为 JSON 格式并处理
      yq -o=json eval "$MODELS_TOML" | jq -r '.models[] | "\(.id)|\(.url)|\(.dir)|\(.fileName // "")"' | while IFS='|' read -r id url dir filename; do
          echo "🎯 开始处理任务: $id"
          echo "📥 下载链接: $url"
          echo "📂 下载目录: $COMFY_DIR$dir"
          echo "📄 文件名: $filename"

          # 确保目录存在
          mkdir -p "$COMFY_DIR$dir"

          # 设置认证头（如果 HF_TOKEN 存在）
          local auth_header=""
          [ -n "$HF_TOKEN" ] && auth_header="Authorization: Bearer $HF_TOKEN"

          # 根据是否存在 fileName 来决定下载参数
          if [ -n "$filename" ]; then
              echo "📄 使用指定文件名: $filename"
              if [ -n "$auth_header" ]; then
                  download_file_by_aria2c "$url" "$filename" "$auth_header" "$COMFY_DIR$dir"
              else
                  download_file_by_aria2c "$url" "$filename" "" "$COMFY_DIR$dir"
              fi
          else
              if [ -n "$auth_header" ]; then
                  download_file_by_aria2c "$url" "$auth_header" "$COMFY_DIR$dir"
              else
                  download_file_by_aria2c "$url" "" "$COMFY_DIR$dir"
              fi
          fi
      done
      echo "✨ 所有模型下载任务处理完成"
  fi
}

# autodl 开启学术加速
if [ -f /etc/network_turbo ]; then
    source /etc/network_turbo
fi

download_file