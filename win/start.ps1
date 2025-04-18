$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 设置错误处理
$ErrorActionPreference = "Stop"

# 获取端口参数
$PORT = if ($args[0]) { $args[0] } else { "8188" }

# 获取脚本路径
$ROOT_DIR = $PSScriptRoot
$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"
Write-Host "脚本所在目录是: $ROOT_DIR"

# 设置Conda路径
$CONDA_PATH = Join-Path $env:USERPROFILE "miniconda3"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
$condaPipPath = "$ENV_PATH\Scripts\pip.exe"
$condaPythonPath = "$ENV_PATH\python.exe"

# 检查并安装Miniconda
if (-not (Test-Path $CONDA_PATH)) {
    Write-Host "🚀 安装 Miniconda..." -ForegroundColor Cyan
    $INSTALLER = Join-Path $ROOT_DIR "miniconda.exe"

    # 下载Miniconda安装程序
    Invoke-WebRequest -Uri "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" -OutFile $INSTALLER

    # 安装Miniconda
    Start-Process -FilePath $INSTALLER -ArgumentList "/InstallationType=JustMe /RegisterPython=0 /S /D=$CONDA_PATH" -Wait
    Remove-Item $INSTALLER

    # 初始化conda
    $env:PATH = "$CONDA_PATH\Scripts;$CONDA_PATH;$env:PATH"
    & $CONDA_PATH\Scripts\conda.exe init powershell
} else {
    Write-Host "✅ Miniconda 已安装" -ForegroundColor Green
}

# 检查并创建环境
$envExists = conda env list | Select-String -Pattern ([regex]::Escape($ENV_PATH))
if (-not $envExists) {
    Write-Host "🚀 创建新的 Python 环境 3.10..." -ForegroundColor Cyan
    Write-Host "📋 当前的 channels 配置：" -ForegroundColor Cyan
    conda config --show channels
    conda create -p $ENV_PATH python=3.10 -y --override-channels -c defaults
    Write-Host "✅ Python 环境创建完成" -ForegroundColor Green
} else {
    Write-Host "✅ Python 环境已存在" -ForegroundColor Green
}

# 激活环境
Write-Host "🚀 激活 Python 环境..." -ForegroundColor Cyan

# 启动ComfyUI
Write-Host "🚀 启动ComfyUI" -ForegroundColor Green
& $condaPythonPath "$COMFY_DIR\main.py" --listen 0.0.0.0 --port $PORT