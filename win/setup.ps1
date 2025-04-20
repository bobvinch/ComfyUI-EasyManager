
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
try {
    if (Test-Path $configFile) {
        $config = Convert-FromToml $configFile
    } else {
        Write-Host "ℹ️ 未找到配置文件，使用默认配置" -ForegroundColor Yellow
        # 提供默认配置
        $config = @{
        # 默认配置项
        }
    }
} catch {
    Write-Warning "无法读取配置文件，使用默认配置"
    $config = @{
    # 默认配置项
    }
}
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


#  引入工具函数
. (Join-Path $ROOT_DIR "tools.ps1")










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



    # 初始化Conda和python环境
    Install-CondaPythonEnvironment


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


    # 使用公共函数解析TOML
    $modelsFile = Join-Path $ROOT_DIR "models.toml"


    Write-Host "开始解析模型配置: $modelsFile" -ForegroundColor Cyan

    try {
        if (Test-Path $modelsFile) {
            $models = Convert-FromToml $modelsFile
        } else {
            Write-Host "未找到模型配置文件，使用默认空配置" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "模型配置解析出现问题，使用默认空配置" -ForegroundColor Yellow
    }
    if ($models -and $models.models -and $models.models.Count -gt 0) {
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
    }

    # 安装huggingface仓库
    Write-Host "🚀 安装huggingface仓库..." -ForegroundColor Cyan
    & "$ROOT_DIR\install_repos_hf.ps1" $HF_TOKEN

    # 启动ComfyUI
    Write-Host "🚀 启动ComfyUI..." -ForegroundColor Green
    & "$ROOT_DIR\start.ps1" $PORT


} catch {
    Handle-Error $_.Exception.Message
}

Write-Host "`n✅ 安装完成！" -ForegroundColor Green
Write-Host "`n按任意键继续..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')