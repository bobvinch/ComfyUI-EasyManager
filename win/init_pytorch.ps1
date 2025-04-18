# 设置错误处理
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 导入TOML解析函数
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "parse_toml.ps1")
# 环境路径设置
$ROOT_DIR = $PSScriptRoot
$envPath = Join-Path $ROOT_DIR "envs\comfyui"
$condaPipPath = "$envPath\Scripts\pip.exe"
$condaPythonPath = "$envPath\python.exe"
$target ="$envPath\Lib\site-packages"
$envName = "comfyui"

Write-Host "📂 脚本根目录: $ROOT_DIR"
Write-Host "📂 环境完整路径: $envPath"

function Initialize-Environment {
    try {
        # 确保目录存在
        if (-not (Test-Path $envPath)) {
            Write-Host "🛠️ 创建目录: $envPath"
            New-Item -ItemType Directory -Path $envPath -Force | Out-Null
        }

        # 检查环境是否已存在
        $pythonExe = Join-Path $envPath "python.exe"
        if (-not (Test-Path $pythonExe)) {
            Write-Host "🛠️ 创建新的 Python 环境..."

            # 先删除可能存在的不完整环境
            if (Test-Path $envPath) {
                Write-Host "🧹 清理已存在的不完整环境..."
                Remove-Item -Path $envPath -Recurse -Force
            }

            # 创建新环境
            $result = & conda create -p $envPath python=3.10 -y 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "环境创建失败: $result"
            }

            # 验证环境创建
            if (-not (Test-Path $pythonExe)) {
                throw "环境创建后未找到 Python 可执行文件"
            }
        }

        # 初始化环境
        Write-Host "🔄 初始化环境..."
        & conda init powershell

        # 设置环境变量
        $env:CONDA_PREFIX = $envPath

        Write-Host "✅ 环境初始化完成"
        return $true
    }
    catch {
        Write-Host "❌ 环境初始化失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "🔍 详细错误信息: $($_.Exception)" -ForegroundColor Yellow
        Write-Host "💡 建议：" -ForegroundColor Yellow
        Write-Host "  1. 确保有足够的磁盘空间" -ForegroundColor Yellow
        Write-Host "  2. 检查 Conda 是否正确安装" -ForegroundColor Yellow
        Write-Host "  3. 尝试手动运行 'conda create -p $envPath python=3.10 -y'" -ForegroundColor Yellow
        return $false
    }
}



function Set-CondaMirrors {
    $condaConfigPath = "$env:USERPROFILE\.condarc"

    $mirrorConfig = @"
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch-lts: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
"@

    Write-Host "🔄 配置 Conda 镜像源..."
    $mirrorConfig | Out-File -FilePath $condaConfigPath -Encoding utf8 -Force

    # 清理缓存并更新
    Write-Host "🧹 清理 Conda 缓存..."
    conda clean -i -y

    # 配置 pip 镜像源
    Write-Host "🔄 配置 pip 镜像源..."

    & $condaPipPath config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

    Write-Host "✅ 镜像源配置完成"
}

function Get-CudaVersion {
    try {
        # 方法1: 使用 nvidia-smi
        $nvidiaSmi = & nvidia-smi --query-gpu=driver_version,cuda_version --format=csv,noheader 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($nvidiaSmi)) {
            $versions = $nvidiaSmi.Trim() -split ','
            if ($versions.Count -ge 2) {
                $driverVersion = $versions[0].Trim()
                $cudaVersion = $versions[1].Trim()
                Write-Host "✅ 通过 nvidia-smi 检测到:"
                Write-Host "  驱动版本: $driverVersion"
                Write-Host "  CUDA 版本: $cudaVersion"
                return $cudaVersion
            }
        }

        # 方法2: 检查 CUDA_PATH 环境变量
        if ($env:CUDA_PATH) {
            if (Test-Path "$env:CUDA_PATH\version.txt") {
                $cudaVersionContent = Get-Content "$env:CUDA_PATH\version.txt"
                if ($cudaVersionContent -match "CUDA Version (\d+\.\d+)") {
                    $cudaVersion = $matches[1]
                    Write-Host "✅ 通过 CUDA_PATH 检测到 CUDA 版本: $cudaVersion"
                    return $cudaVersion
                }
            }
        }

        # 方法3: 检查 Program Files
        $cudaPaths = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA" -ErrorAction SilentlyContinue
        if ($cudaPaths) {
            $latestCuda = $cudaPaths | Sort-Object Name -Descending | Select-Object -First 1
            if ($latestCuda) {
                $cudaVersion = $latestCuda.Name
                Write-Host "✅ 通过安装目录检测到 CUDA 版本: $cudaVersion"
                return $cudaVersion
            }
        }

        # 方法4: 使用 nvcc
        $nvccVersion = & nvcc --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($nvccVersion -match "release (\d+\.\d+)") {
                $cudaVersion = $matches[1]
                Write-Host "✅ 通过 nvcc 检测到 CUDA 版本: $cudaVersion"
                return $cudaVersion
            }
        }

        Write-Host "⚠️ 未能检测到 CUDA" -ForegroundColor Yellow
        return $null
    }
    catch {
        Write-Host "❌ CUDA 检测失败: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-PyTorchInfo {
    try {
        Write-Host "🔍 检查 PyTorch 安装状态..." -ForegroundColor Cyan

        # 使用 Python 脚本验证安装
        $testCode = @"
try:
    import torch
    import json

    result = {
        'installed': True,
        'version': str(torch.__version__),
        'is_cuda': bool(torch.cuda.is_available()),
        'build': str(torch.version.cuda) if torch.cuda.is_available() else 'CPU'
    }
except ImportError:
    result = {
        'installed': False,
        'version': None,
        'is_cuda': False,
        'build': 'Not Installed'
    }

print(json.dumps(result))
"@
        $torchInfo = & $condaPythonPath -c $testCode | ConvertFrom-Json

        if (-not $torchInfo.installed) {
            Write-Host "❌ 未检测到 PyTorch 安装" -ForegroundColor Red
            return @{
                Installed = $false
                IsCuda = $false
                Version = $null
            }
        }

        # 格式化输出
        Write-Host "├─ 版本: $($torchInfo.version)" -ForegroundColor Green
        if ($torchInfo.is_cuda) {
            Write-Host "├─ 类型: CUDA (已启用 GPU 加速)" -ForegroundColor Green
            Write-Host "└─ CUDA 版本: $($torchInfo.build)" -ForegroundColor Gray
        } else {
            Write-Host "├─ 类型: CPU" -ForegroundColor Yellow
            Write-Host "└─ 编译信息: $($torchInfo.build)" -ForegroundColor Gray
        }

        return @{
            Installed = $torchInfo.installed
            IsCuda = $torchInfo.is_cuda
            Version = $torchInfo.version
        }
    }
    catch {
        Write-Host "❌ PyTorch 检测失败: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Installed = $false
            IsCuda = $false
            Version = $null
        }
    }
}


function Get-PyTorchVersion {
    param (
        [string]$cudaVersion
    )

    # PyTorch 版本与 CUDA 版本的完整对应关系
    $versionMap = @{
        '12.4' = @{
            'torch' = '2.5.1'
            'torchvision' = '0.20.1'
            'torchaudio' = '2.5.1'
            'cudaVersion'= '12.4'
            'cuda_suffix' = 'cu124'
        }
        '12.1' = @{
            'torch' = '2.3.1'
            'torchvision' = '0.18.1'
            'torchaudio' = '2.3.1'
            'cudaVersion'= '12.1'
            'cuda_suffix' = 'cu121'
        }
        '11.8' = @{
            'torch' = '2.3.1'
            'torchvision' = '0.18.1'
            'torchaudio' = '2.3.1'
            'cudaVersion'= '11.8'
            'cuda_suffix' = 'cu118'
        }
        '11.7' = @{
            'torch' = '2.0.1'
            'torchvision' = '0.15.1'
            'torchaudio' = '2.0.1'
            'cudaVersion'= '11.7'
            'cuda_suffix' = 'cu117'
        }
        '11.6' = @{
            'torch' = '1.13.1'
            'torchvision' = '0.14.1'
            'torchaudio' = '1.13.1'
            'cudaVersion'= '11.6'
            'cuda_suffix' = 'cu116'
        }
    }

    Write-Host "🔍 检测 CUDA 版本: $cudaVersion"

    try {
        # 清理版本号字符串，移除 'v' 前缀和任何空白
        $cleanVersion = $cudaVersion.Trim().TrimStart('v')

        # 解析 CUDA 版本
        $cudaParts = $cleanVersion.Split('.')
        if ($cudaParts.Count -lt 2) {
            throw "无效的版本格式"
        }

        $cudaMajor = [int]$cudaParts[0]
        $cudaMinor = [int]$cudaParts[1]

        Write-Host "📌 解析后的版本: $cudaMajor.$cudaMinor"

        # CUDA 版本映射逻辑
        switch ($cudaMajor) {
            12 {
                if ($cudaMinor -ge 4) {
                    Write-Host "📌 使用 CUDA 12.4 兼容版本"
                    return $versionMap['12.4']
                }
                elseif ($cudaMinor -ge 1) {
                    Write-Host "📌 使用 CUDA 12.1 兼容版本"
                    return $versionMap['12.1']
                }
                else {
                    Write-Host "📌 使用 CUDA 12.1 兼容版本（向下兼容）"
                    return $versionMap['12.1']
                }
            }
            11 {
                if ($cudaMinor -ge 8) {
                    Write-Host "📌 使用 CUDA 11.8 兼容版本"
                    return $versionMap['11.8']
                }
                elseif ($cudaMinor -ge 7) {
                    Write-Host "📌 使用 CUDA 11.7 兼容版本"
                    return $versionMap['11.7']
                }
                elseif ($cudaMinor -ge 6) {
                    Write-Host "📌 使用 CUDA 11.6 兼容版本"
                    return $versionMap['11.6']
                }
            }
        }

        Write-Host "⚠️ 不支持的 CUDA 版本，使用最新的兼容版本" -ForegroundColor Yellow
        return $versionMap['12.1']
    }
    catch {
        Write-Host "⚠️ CUDA 版本解析失败: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "⚠️ 使用默认版本 (CUDA 12.1)" -ForegroundColor Yellow
        return $versionMap['12.1']
    }
}


function Install-PyTorch {
    param (
        [string]$cudaVersion
    )

    try {
        # 激活环境
        Write-Host "🔄 激活环境..."

        if ($cudaVersion) {
            Write-Host "⚙️ 正在安装CUDA版本的PyTorch..."
            # 获取匹配的版本信息
            $versionInfo = Get-PyTorchVersion -cudaVersion $cudaVersion
            Write-Host "📦 选择的版本信息："
            Write-Host "  PyTorch: $($versionInfo.torch)"
            Write-Host "  TorchVision: $($versionInfo.torchvision)"
            Write-Host "  TorchAudio: $($versionInfo.torchaudio)"
            Write-Host "  CUDA 后缀: $($versionInfo.cuda_suffix)"

            # 直接使用返回的 cuda_suffix
            $packages = $versionInfo

            # 安装 PyTorch
            conda install `
            pytorch==$($packages.torch) `
            torchvision==$($packages.torchvision) `
            torchaudio==$($packages.torchaudio) `
            pytorch-cuda=$($packages.cudaVersion) `
            -p $envPath -c pytorch -c nvidia -y
        }
        else {
            Write-Host "⚙️ 正在安装CPU版本的PyTorch..."
            # 安装 CPU PyTorch
            conda install `
            pytorch==$($packages.torch) `
            torchvision==$($packages.torchvision) `
            torchaudio==$($packages.torchaudio) `
            -p $envPath -c pytorch -y
        }

        # 验证安装
        Write-Host "🔍 验证安装..."
        $testCode = @"
import torch
import torchvision
import torchaudio
print(f'PyTorch 版本: {torch.__version__}')
print(f'CUDA 是否可用: {torch.cuda.is_available()}')
"@
        & $condaPythonPath -c $testCode

        if ($LASTEXITCODE -ne 0) {
            throw "PyTorch 安装验证失败"
        }

        Write-Host "✅ PyTorch 安装完成"
    }
    catch {
        Write-Host "❌ PyTorch安装失败：$($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

try {
    Write-Host "============================"
    Write-Host "🚀 PyTorch 自动初始化工具"
    Write-Host "============================"

    # 配置镜像源
    Set-CondaMirrors

    # 初始化环境并验证
    $envInitialized = Initialize-Environment
    if (-not $envInitialized) {
        throw "环境初始化失败，脚本终止"
    }

    # 检测CUDA
    $cudaVersion = Get-CudaVersion
    if ($cudaVersion) {
        Write-Host "✅ 检测到 CUDA 版本: $cudaVersion"
    }
    else {
        Write-Host "⚠️ 未检测到 CUDA，将安装 CPU 版本"
    }

    # 检测PyTorch
    $pytorch = Get-PyTorchInfo

    if ($pytorch.Installed) {
        Write-Host "📦 当前 PyTorch 信息："
        Write-Host $pytorch.Version

        if ($cudaVersion -and -not $pytorch.IsCuda) {
            Write-Host "⚠️ 检测到CUDA但当前为CPU版本，需要重新安装"
            Install-PyTorch -cudaVersion $cudaVersion
        }
        elseif (-not $cudaVersion -and $pytorch.IsCuda) {
            Write-Host "⚠️ 未检测到CUDA但当前为CUDA版本，需要重新安装"
            Install-PyTorch
        }
        else {
            Write-Host "✅ PyTorch版本匹配，无需重新安装"
        }
    }
    else {
        Write-Host "📥 未检测到PyTorch，开始安装..."
        Install-PyTorch -cudaVersion $cudaVersion
    }

    # 安装 torchsde
    try {
        & $condaPythonPath -c "import torchsde" 2>$null
        Write-Host "✅ torchsde 已安装" -ForegroundColor Green
    } catch {
        Write-Host "⚙️ 正在安装 torchsde..." -ForegroundColor Cyan
        & $condaPipPath install torchsde trampoline>=0.1.2 scipy>=1.5 --no-deps --target $target --no-cache-dir --upgrade
    }

    Write-Host "✅ PyTorch初始化完成！"
    Write-Host "🔧 环境路径: $envPath"
}
catch {
    Write-Host "❌ 错误：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}