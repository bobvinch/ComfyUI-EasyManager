
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
# 设置错误处理
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'  # 加快下载速度

# 导入TOML解析函数
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "parse_toml.ps1")

#HF_TOKEN
$HF_TOKEN = ""

$configFile = Join-Path $ROOT_DIR "config.toml"
$config = Convert-FromToml $configFile
# 配置pip镜像源
if ($config.authorizations -and $config.authorizations.huggingface_token) {
    Write-Host "🔧 检测到配置的huggingface token，已经设置: $($config.authorizations.huggingface_token)" -ForegroundColor Cyan
} else {
    Write-Host "ℹ️ 未配置huggingface token，部分资源可能无效下载" -ForegroundColor Yellow
}

$ROOT_DIR = $PSScriptRoot
# 获取脚本所在目录
Write-Host "脚本所在目录是: $ROOT_DIR"

$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
$condaPipPath = "$ENV_PATH\Scripts\pip.exe"
$condaPythonPath = "$ENV_PATH\python.exe"
# 设置Conda路径
$CONDA_PATH = "C:\Users\$env:USERNAME\miniconda3"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
# 设置默认端口
$PORT = if ($args[0]) { $args[0] } else { "8188" }

# 设置代理
#$env:http_proxy="http://127.0.0.1:10810"
#$env:https_proxy="http://127.0.0.1:10810"

# 获取系统代理设置（仅Windows有效）
$proxyEnabled = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyEnable
$sysProxy = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyServer

if ($proxyEnabled -eq 1 -and $sysProxy) {
    $env:http_proxy = "http://$sysProxy"
    $env:https_proxy = "http://$sysProxy"
    Write-Host "✅ 已启用系统代理: http://$sysProxy" -ForegroundColor Green
} elseif (-not $proxyEnabled) {
    Write-Host "⚠️ 系统代理未启用" -ForegroundColor Yellow
} else {
    Write-Host "⚠️ 未检测到有效的代理设置" -ForegroundColor Yellow
}


# 函数：错误处理
function Handle-Error {
    param($ErrorMessage)
    Write-Host "❌ 错误：$ErrorMessage" -ForegroundColor Red
    Write-Host "按任意键退出..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

# 函数：检查工具是否已安装
function Test-ToolInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    $result = @{
        IsInstalled = $false
        Version = $null
        Path = $null
        Message = ""
    }

    try {
        $cmdInfo = Get-Command $ToolName -ErrorAction Stop
        $result.IsInstalled = $true
        $result.Path = $cmdInfo.Source

        # 尝试获取版本信息
        try {
            $version = & $ToolName --version 2>&1
            $result.Version = $version[0]
        } catch {
            $result.Version = "未知"
        }

        $result.Message = "✅ $ToolName 已安装"
    }
    catch {
        if ($ToolName -eq "choco") {
            $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
            if (Test-Path $chocoPath) {
                $result.IsInstalled = $true
                $result.Path = $chocoPath
                try {
                    $version = & $chocoPath --version 2>&1
                    $result.Version = $version[0]
                } catch {
                    $result.Version = "未知"
                }
                $result.Message = "✅ Chocolatey 已安装"
            } else {
                $result.Message = "❌ Chocolatey 未安装"
            }
        } else {
            $result.Message = "❌ $ToolName 未安装"
        }
    }

    return $result
}


# 刷新环境变量
function Update-EnvPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}


try {
    Write-Host "============================"
    Write-Host "🔄 从远程仓库克隆应用到本地"
    Write-Host "============================"

    # 判断ComfyUI目录是否存在
    if (-not (Test-Path $COMFY_DIR)) {
        Write-Host "🔄 从远程仓库克隆应用到本地"
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git $COMFY_DIR
    }
    else {
        Write-Host "⚠️ ComfyUI已存在（在源目录或目标目录中），跳过克隆步骤"
    }

    Write-Host "============================"
    Write-Host "🔄 开始安装多线程下载工具"
    Write-Host "============================"



    # 检查 Miniconda 是否已安装
    if (-not (Test-Path $CONDA_PATH)) {
        Write-Host "🔄 安装 Miniconda..."
        $MINICONDA_URL = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
        $INSTALLER_PATH = Join-Path $env:TEMP "miniconda.exe"

        Invoke-WebRequest -Uri $MINICONDA_URL -OutFile $INSTALLER_PATH
        Start-Process -FilePath $INSTALLER_PATH -ArgumentList "/S /D=$CONDA_PATH" -Wait
        Remove-Item $INSTALLER_PATH

        # 初始化 conda
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    else {
        Write-Host "✅ Miniconda 已安装"
    }

    # 检查环境是否存在
    $envExists = conda env list | Select-String -Pattern ([regex]::Escape($ENV_PATH))
    if (-not $envExists) {
        Write-Host "🔄 创建新的 Python 环境 3.10..."
        Write-Host "🔄 当前的 channels 配置："
        conda config --show channels
        # 配置 conda 镜像源
        Write-Host "� 配置 conda 镜像源..." -ForegroundColor Cyan
        # 先删除所有已有的镜像源配置
#        conda config --remove-key channels
        # 添加阿里云镜像源
#        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
#        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
#        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/
#        conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/pytorch/
#        conda config --set show_channel_urls yes
#        Write-Host " 配置 conda 镜像源完成" -ForegroundColor Green

        conda config --show channels
        conda create -p $ENV_PATH python=3.10 -y --override-channels -c defaults
        Write-Host "✅ Python 环境创建完成"
        Write-Host "✅ Python 及pytorch 环境创建完成"
    }
    else {
        Write-Host "✅ Python 环境已存在"
    }

    # 激活环境
    Write-Host "🔄 激活 Python 环境..."

    # 安装PyTorch
    Write-Host "🔄 安装PyTorch..."
    .\init_pytorch.ps1


    # 安装ComfyUI及节点的环境依赖
    .\install_requirements.ps1


    # 处理自定义节点
    Push-Location (Join-Path $COMFY_DIR "custom_nodes")

    # 使用Convert-FromToml函数解析TOML文件
    $reposFile = Join-Path $ROOT_DIR "repos.toml"
    $repos = Convert-FromToml $reposFile

    # 安装节点
    foreach ($repo in $repos.repos) {
        # 移除 .git 后缀获取仓库名
        $repoName = Split-Path $repo.url -Leaf
        $repoName = $repoName -replace '\.git$', ''

        Write-Host "🔄 安装节点: $repoName" -ForegroundColor Cyan

        if (-not (Test-Path $repoName)) {
            git clone $repo.url
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ 仓库克隆失败: $repoName" -ForegroundColor Red
                throw "仓库克隆失败: $repoName"
            }
        }
    }
    Pop-Location


    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "🔄 开始安装多线程下载工具" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan

    # 检查是否已安装 aria2c
    $aria2Status = Test-ToolInstalled -ToolName 'aria2c'
    if ($aria2Status.IsInstalled) {
        Write-Host $aria2Status.Message -ForegroundColor Green
        Write-Host "版本: $($aria2Status.Version)"
        Write-Host "路径: $($aria2Status.Path)"
    } else {
        Write-Host "⚙️ 正在安装 aria2c..." -ForegroundColor Cyan
        # 检查 Chocolatey
        $chocoStatus = Test-ToolInstalled -ToolName 'choco'
        if (-not $chocoStatus.IsInstalled) {
            Write-Host "⚙️ 正在安装 Chocolatey..." -ForegroundColor Cyan
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

            # 刷新环境变量
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

            # 验证 Chocolatey 安装
            $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
            if (Test-Path $chocoPath) {
                Write-Host "✅ Chocolatey 安装完成" -ForegroundColor Green
            } else {
                Write-Host "❌ Chocolatey 安装失败" -ForegroundColor Red
                throw "Chocolatey 安装失败"
            }
        }

        # 使用完整路径安装 aria2
        Write-Host "⚙️ 正在通过 Chocolatey 安装 aria2..." -ForegroundColor Cyan
        & "$env:ProgramData\chocolatey\bin\choco.exe" install aria2 -y

        # 刷新环境变量
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        # 验证安装
        $finalStatus = Test-ToolInstalled -ToolName 'aria2c'
        if ($finalStatus.IsInstalled) {
            Write-Host $finalStatus.Message -ForegroundColor Green
            Write-Host "版本: $($finalStatus.Version)"
            Write-Host "路径: $($finalStatus.Path)"
        } else {
            Write-Host $finalStatus.Message -ForegroundColor Red
            throw "aria2c 安装失败"
        }
    }

    # 下载模型
    Push-Location $ROOT_DIR

    # 使用公共函数解析TOML
    $modelsFile = Join-Path $ROOT_DIR "models.toml"
    Write-Host "🔄 开始解析模型,$modelsFile" -ForegroundColor Cyan
    $models = Convert-FromToml $modelsFile
    if (-not $models) {
        Write-Host "❌ 模型解析失败" -ForegroundColor Red
        exit 1
    }
    foreach ($model in $models.models) {
        Write-Host "📦 处理模型: $($model.id)" -ForegroundColor Cyan
        $targetDir = Join-Path $COMFY_DIR $model.dir
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force
        }
        # 修改这部分代码
        if ($model.fileName) {
            # 四个参数的情况：URL, 文件名, 认证头, 目标目录
            & "$ROOT_DIR\download.ps1" `
            "$($model.url)" `
            "$($model.fileName)" `
            "Authorization: Bearer $HF_TOKEN" `
            "$targetDir"
        } else {
            # 三个参数的情况：URL, 认证头, 目标目录
            & "$ROOT_DIR\download.ps1" `
            "$($model.url)" `
            "Authorization: Bearer $HF_TOKEN" `
            "$targetDir"
        }
    }
    Pop-Location

    # 安装huggingface仓库
    Write-Host "🚀 安装huggingface仓库..." -ForegroundColor Cyan
    & "$ROOT_DIR\install_repos_hf.ps1" $HF_TOKEN

    # 启动ComfyUI
    Write-Host "🚀 启动ComfyUI..." -ForegroundColor Green
    & "$ROOT_DIR\start.ps1" $PORT

} catch {
    Handle-Error $_.Exception.Message
    throw
}

Write-Host "`n✅ 安装完成！" -ForegroundColor Green
Write-Host "`n按任意键继续..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')