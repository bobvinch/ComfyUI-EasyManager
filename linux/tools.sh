
# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 获取HF_TOKEN
tools_get_hf_token() {
    CONFIG_TOML="$ROOT_DIR/config.toml"

    local token=""
    if [ -f "$CONFIG_TOML" ]; then
          # 切换到脚本所在目录
          cd "$ROOT_DIR" || exit
          chmod +x parse_toml.sh
        token=$(./parse_toml.sh ./config.toml | jq -r '.authorizations[].huggingface_token // empty')
        if [ "$token" = "null" ]; then
            token=""
        fi
    fi
    echo "$token"
}


export  tools_get_hf_token