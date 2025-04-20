
# 设置Conda路径
$CONDA_PATH = "C:\Users\$env:USERNAME\miniconda3"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
$ROOT_DIR = $PSScriptRoot


function Handle-Error {
    param($ErrorMessage)
    Write-Host "❌ 错误：$ErrorMessage" -ForegroundColor Red
    Write-Host "按任意键退出..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

# 获取配置文件
function Get-ConfigFromFile {
    try {
        $configFile = Join-Path $ROOT_DIR "config.toml"
        $config = Convert-FromToml $configFile
    } catch {
        Write-Warning "无法读取配置文件，使用默认配置"
        $config = @{
        # 默认配置项
        }
    }
    return $config
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


# 初始化Conda环境
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

# 安装Conda的Python 环境
function Install-CondaPythonEnvironment {
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
    # 检查是否已安装 aria2c
    $aria2Status = Test-ToolInstalled -ToolName 'aria2c'
    if ($aria2Status.IsInstalled) {
        Write-Host $aria2Status.Message -ForegroundColor Green
        Write-Host "版本: $($aria2Status.Version)"
        Write-Host "路径: $($aria2Status.Path)"
    } else {

        Write-Host "============================" -ForegroundColor Cyan
        Write-Host " 开始安装多线程下载工具" -ForegroundColor Cyan
        Write-Host "============================" -ForegroundColor Cyan

        Write-Host "⚙️ 正在安装 aria2c..." -ForegroundColor Cyan

        # 检查 Chocolatey
        $chocoStatus = Test-ToolInstalled -ToolName 'choco'
        if (-not $chocoStatus.IsInstalled) {
            Write-Host "⚙️ 正在安装 Chocolatey..." -ForegroundColor Cyan

            # 检查管理员权限
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Error "需要管理员权限才能安装 Chocolatey。请使用管理员身份运行此脚本。"
                throw "权限不足" # 或者根据需要返回 $false 或退出
            }

            try {
                # 设置执行策略 (进程级别，更安全)
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

                # 执行官方安装命令
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

                # 安装后立即刷新环境变量，以便在当前会话中找到 choco
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

                # 重新检查 Chocolatey 安装状态
                $chocoStatus = Test-ToolInstalled -ToolName 'choco'
                if ($chocoStatus.IsInstalled) {
                    Write-Host "✅ Chocolatey 安装完成" -ForegroundColor Green
                } else {
                    # 如果 Test-ToolInstalled 仍然找不到，尝试直接检查路径
                    if (Test-Path "$env:ProgramData\chocolatey\bin\choco.exe") {
                        Write-Host "✅ Chocolatey 安装完成 (路径已确认)" -ForegroundColor Green
                        # 手动将路径添加到当前会话
                        $env:Path += ";$env:ProgramData\chocolatey\bin"
                        $chocoStatus = $true # 假设安装成功以便继续
                    } else {
                        Write-Host "❌ Chocolatey 安装失败" -ForegroundColor Red
                        throw "Chocolatey 安装失败"
                    }
                }
            } catch {
                Write-Host "❌ Chocolatey 安装过程中出错: $_" -ForegroundColor Red
                throw $_
            }
        } else {
            # 如果 Chocolatey 已安装，打印状态信息
            Write-Host "✅ Chocolatey 已安装。" -ForegroundColor Green
            # 确保 choco 在当前会话的 PATH 中 (有时新打开的会话可能没有立即更新)
            $chocoPath = Split-Path -Path ($chocoStatus.Path) -Parent -ErrorAction SilentlyContinue
            if ($chocoPath -and ($env:Path -notlike "*$chocoPath*")) {
                $env:Path += ";$chocoPath"
                Write-Host "  (已将 Chocolatey 路径添加到当前会话 PATH)" -ForegroundColor DarkGray
            }
        }

        # 确保 $chocoStatus 为 $true 或具有 IsInstalled 属性
        if ($chocoStatus -is [hashtable] -and $chocoStatus.IsInstalled -or $chocoStatus -eq $true) {
            # 使用 choco 安装 aria2 (现在应该能直接调用 choco)
            Write-Host "⚙️ 正在通过 Chocolatey 安装 aria2..." -ForegroundColor Cyan
            try {
                # 使用 choco 命令，它应该在 PATH 中
                choco install aria2 -y --force
                # 刷新环境变量以包含 aria2
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } catch {
                Write-Host "❌ 使用 Chocolatey 安装 aria2 时出错: $_" -ForegroundColor Red
                throw $_
            }

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
        } else {
            Write-Host "❌ 未找到 Chocolatey，无法安装 aria2c。" -ForegroundColor Red
            throw "依赖项 Chocolatey 未满足"
        }
    }
}

# 安装 aria2c

function Start-FileWithAria2 {
    param (
        [Parameter(Mandatory = $true)]
        [string]$URL,

        [Parameter(Mandatory = $true)]
        [string]$HEADER,

        [Parameter(Mandatory = $true)]
        [string]$DOWNLOAD_DIR,

        [Parameter(Mandatory = $false)]
        [string]$FILENAME
    )

    # 安装 aria2c
    Install_Aria2

    # 如果没有提供文件名，从URL中提取
    if (-not $FILENAME) {
        $FILENAME = ([System.Uri]$URL).Segments[-1].Split('?')[0]
    }

    Write-Host "解析参数，下载地址：URL: $URL, 文件名：$FILENAME, 认证头：$HEADER, 下载目录：$DOWNLOAD_DIR"

    # 检查下载目录是否存在，不存在则创建
    if (-not (Test-Path $DOWNLOAD_DIR)) {
        Write-Host "📁 创建下载目录: $DOWNLOAD_DIR" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $DOWNLOAD_DIR -Force | Out-Null
    }

    # 完整的下载路径
    $FULL_PATH = Join-Path $DOWNLOAD_DIR $FILENAME

    Write-Host "📥 开始下载..." -ForegroundColor Cyan
    Write-Host "🔗 下载链接: $URL" -ForegroundColor Cyan
    Write-Host "💾 保存为: $FULL_PATH" -ForegroundColor Cyan

    # 检查文件是否已存在
    if (Test-Path $FULL_PATH) {
        # 检查是否是Git LFS占位文件（通常小于200字节）
        $fileSize = (Get-Item $FULL_PATH).Length
        if ($fileSize -lt 200) {
            Write-Host "⚠️ 发现Git LFS占位文件，删除并重新下载: $FULL_PATH" -ForegroundColor Yellow
            Remove-Item $FULL_PATH -Force
        } else {
            Write-Host "⚠️ 文件已存在，跳过下载: $FULL_PATH" -ForegroundColor Yellow
            return $true
        }
    }

    # 使用aria2c下载
    try {
        # 构建 header 参数格式
        $URL = "'$URL'"  # 添加单引号
        $headerArg = "--header=`"$HEADER`""
        $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        $process = Start-Process -FilePath "aria2c" -ArgumentList @(
            "-o", $FILENAME,
            "-d", $DOWNLOAD_DIR,
            "-x", "16",
            "-s", "16",
            "--user-agent=$userAgent",
            $headerArg,
            $URL
        ) -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "✅ 下载完成: $FULL_PATH" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ 下载失败" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ 下载失败: $_" -ForegroundColor Red
        return $false
    }
}
