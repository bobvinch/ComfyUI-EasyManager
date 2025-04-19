
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

function Install-Conda {
    Write-Host "⏳ 安装 Miniconda..."
    $MINICONDA_URL = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
    $INSTALLER_PATH = Join-Path $env:TEMP "miniconda.exe"

    try {
        Invoke-WebRequest -Uri $MINICONDA_URL -OutFile $INSTALLER_PATH
        Start-Process -FilePath $INSTALLER_PATH -ArgumentList "/S /D=$CONDA_PATH" -Wait
        Remove-Item $INSTALLER_PATH

        # 更新环境变量
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"

        # 添加 Conda 相关路径
        $condaScripts = Join-Path $CONDA_PATH "Scripts"
        $env:Path = "$CONDA_PATH;$condaScripts;$env:Path"

        # 初始化 Conda for PowerShell
        $initScript = Join-Path $CONDA_PATH "shell\condabin\conda-hook.ps1"
        if (Test-Path $initScript) {
            & $initScript
            conda init powershell
        }

        # 验证安装
        $retryCount = 0
        while ($retryCount -lt 3) {
            if (Get-Command conda -ErrorAction SilentlyContinue) {
                Write-Host "✅ Conda 安装成功并已初始化" -ForegroundColor Green
                return $true
            }
            Start-Sleep -Seconds 2
            $retryCount++
        }

        Write-Host "⚠️ Conda 已安装但需要重启 PowerShell 才能使用" -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "❌ Conda 安装失败: $_" -ForegroundColor Red
        return $false
    }
}



function Install-CondaEnvironment {
    # 检查 Miniconda 是否已安装
    if (-not (Test-Path $CONDA_PATH)) {
        Install-Conda
    }

    # 验证conda命令是否可用
    $condaCommand = Get-Command conda -ErrorAction SilentlyContinue
    if ($null -eq $condaCommand) {
        Write-Host "❌ Conda命令不可用，请检查安装" -ForegroundColor Red
        Install-Conda
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
}

function Install_Aria2 {
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

            try {
                # 使用用户级别的执行策略
                $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
                Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

                # 使用用户级别安装
                $installScript = Join-Path $env:TEMP "install-choco.ps1"
                (New-Object System.Net.WebClient).DownloadFile('https://community.chocolatey.org/install.ps1', $installScript)
                & $installScript
                Remove-Item $installScript -Force

                # 更新用户级别的环境变量
                $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
                $chocoPath = "$env:USERPROFILE\AppData\Local\chocolatey\bin"
                if ($userPath -notlike "*$chocoPath*") {
                    [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$chocoPath", "User")
                    $env:Path = "$env:Path;$chocoPath"
                }

                # 验证 Chocolatey 安装
                $chocoExe = Join-Path $chocoPath "choco.exe"
                if (Test-Path $chocoExe) {
                    Write-Host "✅ Chocolatey 安装完成" -ForegroundColor Green
                } else {
                    Write-Host "❌ Chocolatey 安装失败" -ForegroundColor Red
                    throw "Chocolatey 安装失败"
                }

                # 恢复原始执行策略
                Set-ExecutionPolicy $currentPolicy -Scope CurrentUser -Force

            } catch {
                Write-Host "❌ 安装过程出错: $_" -ForegroundColor Red
                throw $_
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



    # 初始化Conda环境
    Install-CondaEnvironment


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
        # 安装aria2
        Install_Aria2

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
    throw
}

Write-Host "`n✅ 安装完成！" -ForegroundColor Green
Write-Host "`n按任意键继续..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')