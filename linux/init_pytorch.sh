#!/bin/bash

# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"

CONDA_PATH="/root/miniconda3"
ENV_PATH="$ROOT_DIR/envs/comfyui"

# 获取CUDA版本的函数 12.1, 12.4, 11.8, none
get_cuda_version() {
    if command -v nvidia-smi &> /dev/null; then
        # 使用更精确的匹配方式获取CUDA版本
        cuda_version=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9]+\.[0-9]")
        if [ -n "$cuda_version" ]; then
            echo "$cuda_version"
        else
            echo "none"
        fi
    else
        echo "none"
    fi
}

# 配置conda镜像源
configure_conda_channels() {
    conda config --remove-key channels
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/pytorch
    conda config --set show_channel_urls yes
}


# 安装PyTorch的函数
install_pytorch() {
    local cuda_version=$1
    if [ "$cuda_version" = "none" ]; then
        echo "未检测到 CUDA，将安装 CPU 版本的 PyTorch"
        conda install pytorch torchvision torchaudio cpuonly -p "$ENV_PATH" -c pytorch -y
    else
        echo "检测到 CUDA 版本: $cuda_version，将自动安装对应版本的 PyTorch"
        conda install pytorch torchvision torchaudio -p "$ENV_PATH" -c pytorch -c nvidia -y
    fi
    # 使用 conda 安装 OpenMP 构建环境
    conda install -c conda-forge compilers openmp -y
}


# 检查 PyTorch 安装状态的函数
check_pytorch() {
    if python3 -c "import torch; print(torch.__version__)" &>/dev/null; then
        version=$(python3 -c "import torch; print(torch.__version__)")
        cuda_available=$(python3 -c "import torch; print(torch.cuda.is_available())")
        echo "PyTorch 已安装（版本：$version，CUDA可用：$cuda_available）"
        return 0
    else
        echo "PyTorch 未安装"
        return 1
    fi
}

# 主程序
# 初始化 conda
source "$CONDA_PATH/etc/profile.d/conda.sh"
conda init bash
conda activate "$ENV_PATH"

# 检查 PyTorch 是否已安装
if check_pytorch; then
    echo "✅ PyTorch 已正确安装，跳过安装步骤"
    exit 0
fi

echo "🔧 配置 conda 镜像源..."
configure_conda_channels

echo "🔍 正在检测 CUDA 版本..."
cuda_version=$(get_cuda_version)

if [ "$cuda_version" = "none" ]; then
    echo "💻 未检测到 CUDA，将安装 CPU 版本的 PyTorch"
else
    echo "🎯 检测到 CUDA 版本: $cuda_version"
fi

echo "📦 开始安装 PyTorch..."
install_pytorch "$cuda_version"

echo "✨ PyTorch 安装完成"