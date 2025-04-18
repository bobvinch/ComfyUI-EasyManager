#!/bin/bash

set -e
# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"
ENV_PATH="$ROOT_DIR/envs/comfyui"

cd "$COMFY_DIR/custom_nodes/ComfyUI-Hunyuan3DWrapper" || exit
cd hy3dgen/texgen/custom_rasterizer || exit
# 激活环境
echo "🚀 激活 Python 环境..."
"$ENV_PATH"/bin/python setup.py install

cd "$COMFY_DIR/custom_nodes/ComfyUI-Hunyuan3DWrapper" || exit
cd hy3dgen/texgen/differentiable_renderer
"$ENV_PATH"/bin/python setup.py build_ext --inplace