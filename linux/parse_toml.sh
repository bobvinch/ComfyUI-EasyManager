
# 检查输入文件
if [ "$#" -ne 1 ]; then
    echo "使用方法: $0 <config.toml>"
    exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 使用 yq 将 TOML 转换为 JSON，然后用 jq 格式化
yq -p=toml -o=json eval "$CONFIG_FILE" | jq '.'