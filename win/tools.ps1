
# 设置Conda路径
$CONDA_PATH = "C:\Users\$env:USERNAME\miniconda3"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"


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
