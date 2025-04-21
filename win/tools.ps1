$ROOT_DIR = $PSScriptRoot
# 设置Conda路径
$CONDA_PATH = "C:\Users\$env:USERNAME\miniconda3"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
$condaPipPath = "$ENV_PATH\Scripts\pip.exe"
$condaPythonPath = "$ENV_PATH\python.exe"
$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"

# 引入TOML解析函数
. (Join-Path $ROOT_DIR "parse_toml.ps1")

# 函数：处理错误,一般只能用在主函数中
function Handle-Error {
    param($ErrorMessage)
    Write-Host "❌ 错误：$ErrorMessage" -ForegroundColor Red
    Write-Host "`n按 Enter 键退出..." -ForegroundColor Cyan
    do {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } until ($key.VirtualKeyCode -eq 13) # 13 是 Enter 键的虚拟键码
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
# 获取HF_TOKEN从配置文件
function Get-HF_TOKEN {
    $config = Get-ConfigFromFile
    if ($config.authorizations -and $config.authorizations.huggingface_token) {
        return $config.authorizations.huggingface_token
    } else {
        return $null
    }
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

    # 刷新环境变量
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 定义常见的版本参数
    $versionParams = @(
        '--version',
        '-v',
        '-V',
        'version',
        '--ver',
        '-version'
    )

    try {
        # 首先尝试直接使用 Get-Command
        $cmdInfo = Get-Command $ToolName -ErrorAction Stop

        if (Test-Path $cmdInfo.Source) {
            $result.IsInstalled = $true
            $result.Path = $cmdInfo.Source

            # 尝试获取版本信息
            $versionFound = $false
            foreach ($param in $versionParams) {
                try {
                    $versionOutput = & $cmdInfo.Source $param 2>&1
                    if ($versionOutput) {
                        # 尝试从输出中提取版本号
                        $versionPattern = '(?i)(?:version|v)?\s*(\d+(?:\.\d+)*(?:-\w+)?)'
                        if ($versionOutput[0] -match $versionPattern) {
                            $result.Version = $matches[1]
                            $versionFound = $true
                            break
                        } else {
                            # 如果没有匹配到版本号格式，使用第一行输出
                            $result.Version = $versionOutput[0]
                            $versionFound = $true
                            break
                        }
                    }
                } catch {
                    continue
                }
            }

            if (-not $versionFound) {
                $result.Version = "未知"
            }

            $result.Message = "✅ $ToolName 已安装"
        } else {
            throw "命令路径无效"
        }
    }
    catch {
        # 如果 Get-Command 失败，尝试在常见安装路径中查找
        $commonPaths = @(
            "${env:ProgramFiles}\$ToolName\$ToolName.exe",
            "${env:ProgramFiles(x86)}\$ToolName\$ToolName.exe",
            "$env:ProgramData\chocolatey\bin\$ToolName.exe",
            "${env:ProgramFiles}\$ToolName\bin\$ToolName.exe",
            "${env:ProgramFiles(x86)}\$ToolName\bin\$ToolName.exe",
            "$env:LOCALAPPDATA\Programs\$ToolName\$ToolName.exe",
            "$env:APPDATA\$ToolName\$ToolName.exe",
            "$env:ChocolateyInstall\bin\$ToolName.exe"
        )

        # 添加特定工具的自定义路径
        switch ($ToolName) {
            "choco" {
                $commonPaths += "$env:ProgramData\chocolatey\bin\choco.exe"
            }
            "aria2c" {
                $commonPaths += @(
                    "${env:ProgramFiles}\aria2\aria2c.exe",
                    "$env:ChocolateyInstall\bin\aria2c.exe"
                )
            }
            # 可以在这里添加其他特定工具的路径
        }

        $foundPath = $commonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($foundPath) {
            $result.IsInstalled = $true
            $result.Path = $foundPath

            # 尝试获取版本信息
            $versionFound = $false
            foreach ($param in $versionParams) {
                try {
                    $versionOutput = & $foundPath $param 2>&1
                    if ($versionOutput) {
                        $versionPattern = '(?i)(?:version|v)?\s*(\d+(?:\.\d+)*(?:-\w+)?)'
                        if ($versionOutput[0] -match $versionPattern) {
                            $result.Version = $matches[1]
                            $versionFound = $true
                            break
                        } else {
                            $result.Version = $versionOutput[0]
                            $versionFound = $true
                            break
                        }
                    }
                } catch {
                    continue
                }
            }

            if (-not $versionFound) {
                $result.Version = "未知"
            }

            $result.Message = "✅ $ToolName 已安装"
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
        return # 已安装，无需继续
    }

    Write-Host "============================" -ForegroundColor Cyan
    Write-Host " 开始安装多线程下载工具 aria2" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    # 初始化 winget
    Initialize-Winget

    # 标记是否已成功安装
    $installedSuccessfully = $false

    # 1. 尝试使用 winget 安装
    Write-Host "⚙️ 正在尝试使用 winget 安装 aria2c..." -ForegroundColor Cyan
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) {
        Write-Host "  检测到 winget，尝试安装..."
        try {
            # 使用 winget 安装，--accept* 参数用于非交互式安装
            winget install --id aria2.aria2 --source winget --accept-package-agreements --accept-source-agreements --silent

            # 刷新当前会话的环境变量
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            # 等待一小段时间确保安装完成和 PATH 更新
            Start-Sleep -Seconds 5
            # 重新检查安装状态
            $aria2Status = Test-ToolInstalled -ToolName 'aria2c'
            if ($aria2Status.IsInstalled) {
                Write-Host "✅ 使用 winget 成功安装 aria2c。" -ForegroundColor Green
                Write-Host "版本: $($aria2Status.Version)"
                Write-Host "路径: $($aria2Status.Path)"
                $installedSuccessfully = $true
            } else {
                Write-Host "⚠️ 使用 winget 安装 aria2c 后仍未检测到，将尝试 Chocolatey。" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠️ 使用 winget 安装 aria2c 时出错: $_" -ForegroundColor Yellow
            Write-Host "  将尝试使用 Chocolatey 安装。" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  未检测到 winget，跳过 winget 安装，使用choco 安装aria2c。" -ForegroundColor DarkGray
    }

    # 2. 如果 winget 安装失败或未尝试，则使用 Chocolatey 安装
    if (-not $installedSuccessfully) {
        Write-Host "⚙️ 正在尝试使用 Chocolatey 安装 aria2c..." -ForegroundColor Cyan

        # 检查 Chocolatey
        $chocoStatus = Test-ToolInstalled -ToolName 'choco'
        if (-not $chocoStatus.IsInstalled) {
            Write-Host "⚙️ 正在安装 Chocolatey..." -ForegroundColor Cyan
            # 检查管理员权限
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Error "需要管理员权限才能安装 Chocolatey。请使用管理员身份运行此脚本。"
                throw "权限不足"
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
                        $chocoStatus = @{ IsInstalled = $true; Path = "$env:ProgramData\chocolatey\bin\choco.exe" } # 模拟 Test-ToolInstalled 的输出
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
            # 确保 choco 在当前会话的 PATH 中
            $chocoPathDir = Split-Path -Path ($chocoStatus.Path) -Parent -ErrorAction SilentlyContinue
            if ($chocoPathDir -and ($env:Path -notlike "*$chocoPathDir*")) {
                $env:Path += ";$chocoPathDir"
                Write-Host "  (已将 Chocolatey 路径添加到当前会话 PATH)" -ForegroundColor DarkGray
            }
        }

        # 确保 $chocoStatus 表示已安装
        if (($chocoStatus -is [hashtable] -and $chocoStatus.IsInstalled) -or ($chocoStatus -eq $true)) {
            # 使用 choco 安装 aria2
            Write-Host "⚙️ 正在通过 Chocolatey 安装 aria2..." -ForegroundColor Cyan
            try {
                # 使用 choco 命令
                choco install aria2 -y --force
                # 刷新环境变量以包含 aria2
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                # 等待一小段时间
                Start-Sleep -Seconds 5
                # 再次检查 aria2 安装状态
                $aria2Status = Test-ToolInstalled -ToolName 'aria2c'
                if ($aria2Status.IsInstalled) {
                    $installedSuccessfully = $true
                }
            } catch {
                Write-Host "❌ 使用 Chocolatey 安装 aria2 时出错: $_" -ForegroundColor Red
                # 不再抛出错误，而是继续到最后的检查
            }
        } else {
            Write-Host "❌ 未找到 Chocolatey 或安装失败，无法通过 Chocolatey 安装 aria2c。" -ForegroundColor Red
        }
    }

    # 最终验证安装结果
    if ($installedSuccessfully) {
        # 如果上面已经打印过成功信息，这里可以不再重复打印，或者只打印最终确认
        Write-Host "✅ aria2c 已成功安装并可用。" -ForegroundColor Green
        # 可以选择再次获取状态并打印
        $finalStatus = Test-ToolInstalled -ToolName 'aria2c'
        if ($finalStatus.IsInstalled) {
            Write-Host "版本: $($finalStatus.Version)"
            Write-Host "路径: $($finalStatus.Path)"
        }
    } else {
        Write-Host "❌ 未能成功安装 aria2c。请检查错误信息并尝试手动安装。" -ForegroundColor Red
        # 可以选择抛出错误，让脚本停止
        # throw "aria2c 安装失败"
    }
}

# 安装 aria2c

function Start-FileDownloadWithAria2 {
    param (
        [Parameter(Mandatory = $true)]
        [string]$URL,

        [Parameter(Mandatory = $false)]
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
        # 检查是否存在.aria2c临时文件
        $aria2cFile = "$FULL_PATH.aria2"
        if (Test-Path $aria2cFile) {
            Write-Host "⚠️ 发现未完成的下载任务，继续下载: $FULL_PATH" -ForegroundColor Yellow
        } else {
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
    }

    # 使用aria2c下载
    try {
        # 构建基础参数列表
        $arguments = @()

        # 添加基本下载参数
        $arguments += "-o", $FILENAME
        $arguments += "-d", $DOWNLOAD_DIR
        $arguments += "-x", "16"
        $arguments += "-s", "16"
        $arguments += "--user-agent=`"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36`""

        # 如果存在 Header 且不为空，则添加到参数列表（用引号包裹整个 header）
        if (-not [string]::IsNullOrWhiteSpace($HEADER)) {
            $arguments += "--header=`"$HEADER`""
        }

        # 添加 URL（用引号包裹）
        $arguments += "`"$URL`""

        # 输出实际执行的命令用于调试
        Write-Host "执行命令: aria2c $($arguments -join ' ')" -ForegroundColor Yellow



        $process = Start-Process -FilePath "aria2c" `
                           -ArgumentList $arguments `
                           -NoNewWindow `
                           -Wait `
                           -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "✅ 下载完成: $FULL_PATH" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ 下载失败，退出码: $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ 下载失败: $_" -ForegroundColor Red
        return $false
    }
}

# 安装 Winget
function Initialize-Winget {
    # 检查是否已安装 winget
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) {
        Write-Host "✅ winget 已安装" -ForegroundColor Green
        Write-Host "版本: $((winget --version).Trim())"
        Write-Host "路径: $($wingetPath.Path)"
        return $true
    }

    Write-Host "============================" -ForegroundColor Cyan
    Write-Host " 开始安装 winget" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan

    # 检查系统版本
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Host "❌ winget 需要 Windows 10 或更高版本" -ForegroundColor Red
        return $false
    }

    # 检查是否安装了应用安装程序
    $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if (-not $appInstaller) {
        Write-Host "⚙️ 正在安装 App Installer..." -ForegroundColor Cyan
        try {
            # 下载最新的 App Installer
            $releases = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $msixBundleUrl = (Invoke-RestMethod -Uri $releases).assets |
                    Where-Object { $_.name -like "*.msixbundle" } |
                    Select-Object -ExpandProperty browser_download_url

            $tempFile = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
            Invoke-WebRequest -Uri $msixBundleUrl -OutFile $tempFile

            # 安装 App Installer
            Add-AppxPackage -Path $tempFile

            # 清理临时文件
            Remove-Item $tempFile -Force

            # 刷新环境变量
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

            # 等待安装完成
            Start-Sleep -Seconds 5

            # 验证安装
            $wingetCheck = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCheck) {
                Write-Host "✅ winget 安装成功" -ForegroundColor Green
                Write-Host "版本: $((winget --version).Trim())"
                Write-Host "路径: $($wingetCheck.Path)"
                return $true
            } else {
                Write-Host "⚠️ winget 已安装但需要重启 PowerShell 才能生效" -ForegroundColor Yellow
                return $true
            }
        }
        catch {
            Write-Host "❌ winget 安装失败: $_" -ForegroundColor Red
            Write-Host "请尝试从 Microsoft Store 手动安装 'App Installer'" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "✅ App Installer 已安装，正在更新..." -ForegroundColor Green
        try {
            # 尝试更新 App Installer
            Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" |
                    Invoke-CimMethod -MethodName UpdateScanMethod

            Write-Host "✅ App Installer 更新检查完成" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "⚠️ App Installer 更新检查失败: $_" -ForegroundColor Yellow
            return $true # 返回 true 因为 winget 仍然可用
        }
    }
}

function Start_DownloadUserConfigModels {
    param (
        [Parameter(Mandatory = $false)]
        [Boolean]$isInteractive = $false
    )
    # 下载模型
    # 使用公共函数解析TOML
    $modelsFile = Join-Path $ROOT_DIR "models.toml"

    Write-Host "开始解析模型配置: $modelsFile" -ForegroundColor Cyan
    # 创建空数组
    $models = @{}

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
        # 定义模型的HF_TOKEN
        $HF_TOKEN = Get-HF_TOKEN

        foreach ($model in $models.models) {
            Write-Host "📦 处理模型: $($model.id)" -ForegroundColor Cyan

            $targetDir = Join-Path $COMFY_DIR $model.dir
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force
            }

            # 调用 Start-FileDownload 函数
            $params = @{
                URL = $model.url
                DOWNLOAD_DIR = $targetDir
            }
            if($HF_TOKEN){
                $params.HEADER = "Authorization: Bearer $HF_TOKEN"
            }

            if ($model.fileName) {
                $params.FILENAME = $model.fileName
            }
            # 调用工具函数下载模型
            Start-FileDownloadWithAria2 @params
        }
    }
    else
    {
        Write-Host "未找到模型配置，跳过下载" -ForegroundColor Yellow
    }

    if ($isInteractive) {
        Write-Host "`n按 Enter 键退出..." -ForegroundColor Cyan
        do {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } until ($key.VirtualKeyCode -eq 13) # 13 是 Enter 键的虚拟键码
    }
}



# 定义依赖安装函数
function Install-Requirements {
    param (
        [string]$ReqFile,
        [string]$Context
    )

    if (-not (Test-Path $ReqFile)) {
        Write-Host "⚠️ 未找到依赖文件: $ReqFile" -ForegroundColor Yellow
        return $false
    }

    Write-Host "📦 检查${Context}依赖..." -ForegroundColor Cyan

    # 获取已安装的包列表
    Write-Host "🔍 获取已安装包列表..." -ForegroundColor Cyan
    $installedPackages = @{}
    & $condaPipPath list --format=freeze | ForEach-Object {
        if ($_ -match '^([^=]+)==.*$') {
            $installedPackages[$Matches[1]] = $true
        }
    }

    # 创建需要安装的包列表
    $toInstall = @()

    # 读取requirements文件
    Get-Content $ReqFile | ForEach-Object {
        $package = $_.Trim()

        # 跳过空行和注释行
        if ($package -and -not $package.StartsWith("#")) {
            # 提取包名
            if ($package -match '^([^=>< ]+)') {
                $pkgName = $Matches[1]

                if ($installedPackages.ContainsKey($pkgName)) {
                    Write-Host "✅ $pkgName 已安装，跳过" -ForegroundColor Green
                } else {
                    Write-Host "📝 添加 $pkgName 到安装列表" -ForegroundColor Cyan
                    $toInstall += $package
                }
            }
        }
    }

    # 定义要排除的包名，torch相关的包通过conda管理，避免其他包被误安装
    $excludePackages = @(
        'torch',
        'torchvision',
        'torchaudio'
    )

    # 过滤torch相关的包和版本控制
    $toInstall = $toInstall | ForEach-Object {
        $package = $_
        # 去除 Python 版本约束后缀 (如 package>=3.6)
        $packageName = ($package -split '[<>=]')[0].Trim()

        # 检查是否是需要排除的包
        if ($excludePackages | Where-Object { $packageName -like "*$_*" }) {
            return $null
        }

        # 检查是否在 TOML 配置中有指定版本
        $configVersion = $config.packages.$packageName
        if ($configVersion) {
            # 使用配置文件中指定的版本
            return $configVersion
            Write-Host "📝 包强制版本控制，添加 $packageName 到安装列表" -ForegroundColor Cyan
        }
        # 如果没有在配置中指定版本，使用原始包名
        return $package
    } | Where-Object { $_ -ne $null }


    # 批量安装未安装的包
    if ($toInstall.Count -gt 0) {
        # 过滤掉 PyTorch 相关的包
        $toInstall = $toInstall | Where-Object {
            $_ -notmatch 'torch|torchvision|torchaudio'
        }

        if ($toInstall.Count -gt 0) {
            Write-Host "� 开始安装缺失的依赖..." -ForegroundColor Cyan
            $total = $toInstall.Count
            $current = 0
            try {
                if ($PIP_MIRROR) {
                    & $condaPipPath install $toInstall -i $PIP_MIRROR --no-warn-script-location  --progress-bar on

                } else {

                    & $condaPipPath install $toInstall --no-cache-dir --no-warn-script-location --progress-bar on

                }
                Write-Host "✅ 所有依赖安装完成" -ForegroundColor Green
            } catch {
                Write-Host "❌ 部分依赖安装失败: $_" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "✅ 无需安装其他依赖" -ForegroundColor Green
        }
    }

    Write-Host "✅ ${Context}依赖检查完成" -ForegroundColor Green
    return $true
}

function Get-CondaPackageInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$EnvPath,

        [Parameter(Mandatory=$true)]
        [string]$PackageName
    )

    try {
        # 使用 pip show 获取详细包信息
        $packageInfo = & $condaPipPath show $PackageName --target $EnvPath 2>$null

        if ($LASTEXITCODE -eq 0 -and $packageInfo) {
            # 提取版本信息
            $versionLine = $packageInfo | Select-String "^Version:\s*(.+)$"
            $version = if ($versionLine) {
                $versionLine.Matches.Groups[1].Value.Trim()
            } else {
                $null
            }

            return @{
                IsInstalled = $true
                Version = $version
                BuildString = $null
                Channel = $null
            }
        } else {
            return @{
                IsInstalled = $false
                Version = $null
                BuildString = $null
                Channel = $null
            }
        }
    }
    catch {
        Write-Host "❌ 获取包信息时出错: $_" -ForegroundColor Red
        return @{
            IsInstalled = $false
            Version = $null
            BuildString = $null
            Channel = $null
        }
    }
}

# 从numpy == 1.36.4 字符串中提取包名和版本号
function Get-PackageVersionInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$VersionString
    )

    try {
        # 清理输入字符串
        $VersionString = $VersionString.Trim()

        # 匹配版本号和操作符（支持操作符前后可选的空格）
        if ($VersionString -match "(\S+)\s*([<>=]=?)\s*(\S+)") {
            return @{
                PackageName = $Matches[1].Trim()    # 包名并清理空格
                Operator = $Matches[2].Trim()       # 操作符并清理空格
                Version = $Matches[3].Trim()        # 版本号并清理空格
                Success = $true
            }
        }

        # 如果没有匹配到操作符，返回原始包名
        return @{
            PackageName = $VersionString
            Operator = $null
            Version = $null
            Success = $false
        }
    }
    catch {
        Write-Host "❌ 版本字符串解析失败: $_" -ForegroundColor Red
        return $null
    }
}

# 版本比较函数
function Compare-Versions {
    param (
        [string]$Version1,
        [string]$Version2
    )

    try {
        # 提取纯数字版本部分
        $v1Numbers = ($Version1 -split '[a-zA-Z]')[0]
        $v2Numbers = ($Version2 -split '[a-zA-Z]')[0]

        # 转换为版本对象
        $v1 = [System.Version]$v1Numbers
        $v2 = [System.Version]$v2Numbers

        # 如果数字部分相同，比较后缀
        if ($v1 -eq $v2) {
            $v1Suffix = ($Version1 -replace '[0-9\.]', '').ToLower()
            $v2Suffix = ($Version2 -replace '[0-9\.]', '').ToLower()

            # 处理后缀比较（rc < '' < beta < alpha）
            $suffixOrder = @{
                'rc' = 3
                '' = 4
                'b' = 1
                'beta' = 1
                'a' = 0
                'alpha' = 0
            }

            $v1Value = $suffixOrder[$v1Suffix]
            $v2Value = $suffixOrder[$v2Suffix]

            return $v1Value.CompareTo($v2Value)
        }

        # 返回数字版本的比较结果
        return $v1.CompareTo($v2)
    }
    catch {
        Write-Host "❌ 版本比较失败: $_" -ForegroundColor Red
        return 0
    }
}

function Test-PackageUpgradeNeeded {
    param (
        [Parameter(Mandatory=$true)]
        [string]$VersionRequirement,

        [Parameter(Mandatory=$true)]
        [string]$CurrentVersion
    )

    try {
        # 清理版本字符串
        $VersionRequirement = $VersionRequirement.Trim()
        $CurrentVersion = $CurrentVersion.Trim()


        # 修改正则表达式，使用非贪婪匹配并明确指定操作符
        if ($VersionRequirement -match "(\S+?)\s*(==|>=|<=|>|<)\s*(\S+)") {
            $packageName = $Matches[1].Trim()
            $operator = $Matches[2].Trim()
            $requiredVersion = $Matches[3].Trim()


            $compareResult = Compare-Versions $CurrentVersion $requiredVersion

            $needUpgrade = switch ($operator) {
                "==" { $compareResult -ne 0 }    # 不相等时需要更新
                ">=" { $compareResult -lt 0 }    # 当前版本小于要求版本时需要更新
                "<=" { $compareResult -gt 0 }    # 当前版本大于要求版本时需要更新
                ">" { $compareResult -le 0 }     # 当前版本小于等于要求版本时需要更新
                "<" { $compareResult -ge 0 }     # 当前版本大于等于要求版本时需要更新
            }
            return $needUpgrade
        }
        # 如果没有操作符，且当前版本不为空，则不需要升级
        elseif ($CurrentVersion) {
            return $false
        }
        # 如果没有操作符，且当前版本为空，则需要安装
        else {
            return $true
        }
    }
    catch {
        Write-Host "❌ 版本比较出错: $_" -ForegroundColor Red
        return $false
    }
}

# 遍历自定义节点目录安装依赖
function Install-CustomNodeRequirements {

    $customNodesPath = Join-Path $COMFY_DIR "custom_nodes"

    Write-Host "开始检查自定义节点依赖..." -ForegroundColor Cyan

    # 确保目录存在
    if (-not (Test-Path $CustomNodesPath)) {
        Write-Host "自定义节点目录不存在: $CustomNodesPath" -ForegroundColor Red
        return
    }

    # 获取所有子目录
    $nodeFolders = Get-ChildItem -Path $CustomNodesPath -Directory

    Write-Host "共有" $nodeFolders.Count "个自定义节点，开始遍历自定义节点目录..." -ForegroundColor Cyan


    foreach ($folder in $nodeFolders) {
        # 重新检查和分析依赖分件
        #        conda run -p $ENV_PATH pipreqs $folder.FullName --force --noversion

        $reqFile = Join-Path $folder.FullName "requirements.txt"

        if (Test-Path $reqFile) {
            Write-Host "发现依赖文件: $($folder.Name)" -ForegroundColor Green

            try {
                Install-Requirements -ReqFile $reqFile -Context $folder.Name
            } catch {
                Write-Host "安装依赖失败 ($($folder.Name)): $_" -ForegroundColor Red
            }
        } else {
            Write-Host "跳过 $($folder.Name): 未找到 requirements.txt" -ForegroundColor Yellow
        }
    }

    Write-Host "自定义节点依赖检查完成" -ForegroundColor Cyan
}

# 检查依赖冲突
function Test-DependencyConflicts {
    Write-Host "🔍 检查依赖冲突..." -ForegroundColor Cyan

    $noConflictsOutput="No broken requirements found."

    # 执行 pip check 并捕获输出
    $checkOutput = & $condaPipPath check 2>&1

    Write-Host "🔍 检测依赖冲突的检查结果输出："$checkOutput

    # 如果没有输出，说明没有依赖问题
    if (-not $checkOutput -or $checkOutput -eq $noConflictsOutput) {
        Write-Host "✅ 所有依赖关系正常" -ForegroundColor Green
        return
    }

    Write-Host "⚠️ 检测到依赖冲突，开始分析..." -ForegroundColor Yellow
    $toUpgrade = @()

    # 解析每一行输出
    foreach ($line in $checkOutput) {
        # 更新正则表达式以更精确匹配 Windows pip check 输出格式
        if ($line -match "([^\s]+)\s+([^\s]+)\s+has\s+requirement\s+([^\s]+)==([^,\s]+),\s+but\s+you\s+have\s+([^\s]+)\s+([^\s]+)") {
            $parentPkg = $matches[1]    # 父包名
            $parentVer = $matches[2]    # 父包版本
            $pkgName = $matches[3]      # 依赖包名
            $requiredVer = $matches[4]  # 需求版本
            $currentPkg = $matches[5]   # 当前包名（验证用）
            $currentVer = $matches[6]   # 当前版本

            # 验证包名匹配
            if ($pkgName -eq $currentPkg) {
                Write-Host "📦 检测到版本冲突: $pkgName" -ForegroundColor Yellow
                Write-Host "   - 当前版本: $currentVer" -ForegroundColor White
                Write-Host "   - 需求版本: ==$requiredVer" -ForegroundColor White
                Write-Host "   - 来自包: $parentPkg $parentVer" -ForegroundColor White

                $toUpgrade += @{
                    Name = $pkgName
                    Version = $requiredVer
                }
            }
        }
    }

    # 执行修复
    if ($toUpgrade.Count -gt 0) {
        Write-Host "🔧 开始修复依赖问题..." -ForegroundColor Cyan

        foreach ($package in $toUpgrade) {
            Write-Host "🗑️ 卸载 $($package.Name)..." -ForegroundColor Yellow
            & $condaPipPath uninstall -y $package.Name

            $installSpec = "$($package.Name)==$($package.Version)"
            Write-Host "📥 安装 $installSpec..." -ForegroundColor Cyan

            try
            {
                $installResult = & $condaPipPath install $installSpec 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "⚠️ 安装 $installSpec 失败" -ForegroundColor Yellow
                }
            }
            catch
            {
                Write-Host "⚠️ 安装 $installSpec 失败,可能需要手动指定版本或者手动安装" -ForegroundColor Red
                continue
            }
        }

        # 最终检查
        $finalCheck = & $condaPipPath check 2>&1
        if ($finalCheck -match $noConflictsOutput -or -not $finalCheck) {
            Write-Host "✨ 所有依赖问题已修复" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ 仍存在依赖问题，可能需要手动处理" -ForegroundColor Red
            Write-Host $finalCheck
        }
    }
    else {
        Write-Host "✨ 未检测到需要修复的依赖" -ForegroundColor Green
    }
}

# 安装用户自定义依赖
function Install-UserDefinedRequirements {
    if(Test-Path $configFile){
        $config = Convert-FromToml $configFile
        #将packages里的包，全部添加到toInstall中
        if ($config.packages) {
            $config.packages | Get-Member -MemberType NoteProperty | ForEach-Object {
                $packageName = $_.Name
                $versionString = $config.packages.$packageName
                #判断是否已经安装和安装的版本是否一致
                $isInstalled =$false
                $versionOld = ''
                try
                {
                    $installedInfo = & $condaPipPath show $packageName 2>$null
                    $installedVersion = ($installedInfo | Select-String "^Version:\s*(.+)$").Matches.Groups[1].Value
                    if ($installedVersion) {
                        $isInstalled = $true
                        $versionOld = $installedVersion
                    }
                    else {
                        $isInstalled = $false
                    }
                }
                catch
                {
                    $isInstalled = $false
                }

                Write-Host "📦 包信息: "$packageName"安装状态：" $isInstalled

                if ($versionString) {
                    # version格式是sympy==1.13.1或者sympy>=1.13.1格式，需要处理获取纯的版本号
                    $versionObj = Get-PackageVersionInfo -VersionString $versionString
                    $versionNew = $versionObj.Version
                    $needUpdate =Test-PackageUpgradeNeeded -CurrentVersion $versionOld -VersionRequirement $versionString

                    if($isInstalled -and -not $needUpdate){
                        Write-Host "📦 包已经安装，且版本一致，跳过安装: 包名: $packageName, 版本: $versionNew" -ForegroundColor Green
                        return
                    }
                    # 强制更新
                    Write-Host "📦 正在强制更新安装包: 包名: $packageName,旧版本:$versionOld, 新版本: $versionNew" -ForegroundColor Yellow
                    & $condaPipPath uninstall $packageName --yes
                    & $condaPipPath install $versionString  --force-reinstall --no-deps --upgrade --no-cache-dir --progress-bar on
                } else {
                    if($isInstalled){
                        Write-Host "📦 包已经安装，跳过安装: 包名: $packageName" -ForegroundColor Green
                        return
                    }
                    Write-Host "📦 正在安装包: 包名: $packageName" -ForegroundColor Yellow
                    & $condaPipPath install $packageName  --force-reinstall --no-deps --upgrade --no-cache-dir --progress-bar on
                }
            }
        }
    }

}




# 初始化下载工具
function Initialize-DownloadTools {
    # 检查必要工具
    $tools = @{
        "aria2c" = {
            choco install aria2 -y
        }
        "git-lfs" = {
            choco install git-lfs -y
            git lfs install
        }
    }
    # 读取 TOML 文件
    $REPOS_FILE = Join-Path $ROOT_DIR "repos_hf.toml"
    if (-not (Test-Path $REPOS_FILE)) {
        Write-Host "❌ 未找到huggingface 仓库配置文件：$REPOS_FILE" -ForegroundColor Red
    }
    else
    {
        # 只有在配置了仓库的情况下才检查并安装必要工具，减少初次启动的错误
        foreach ($tool in $tools.Keys)
        {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue))
            {
                Write-Host "⚙️ 安装 $tool..." -ForegroundColor Cyan
                & $tools[$tool]
            }
        }
    }
}

# 执行安装仓库
function Install-HuggingfaceRepos {
    param (
        [Parameter(Mandatory = $false)]
        [Boolean]$isInteractive = $false
    )

    # 安装工具
    Initialize-DownloadTools

    # 读取 TOML 文件
    $REPOS_FILE = Join-Path $ROOT_DIR "repos_hf.toml"
    if (-not (Test-Path $REPOS_FILE)) {
        Write-Host "❌ 未找到huggingface 仓库配置文件：$REPOS_FILE" -ForegroundColor Red
    }
    else
    {
        # 检查并安装必要工具
        foreach ($tool in $tools.Keys) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                Write-Host "⚙️ 安装 $tool..." -ForegroundColor Cyan
                & $tools[$tool]
            }
        }

        # 获取 HF_TOKEN
        $HF_TOKEN = Get-HF_TOKEN

        # 解析 TOML 文件
        $repos = Convert-FromToml $REPOS_FILE
        # 获取配置文件

        if($HF_TOKEN){
            # 配置 git 凭证
            git config --global credential.helper store
            git config --global init.defaultBranch main
            "https://USER:${HF_TOKEN}@huggingface.co" | Out-File -FilePath (Join-Path $HOME ".git-credentials")
        }


        foreach ($repo in $repos.repos) {
            $repo_name = Split-Path $repo.url -Leaf
            $fullPath = Join-Path $COMFY_DIR "$($repo.local_path)/$repo_name"

            # 创建目标目录
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null

            # 保存当前目录
            $previousLocation = Get-Location
            Set-Location $fullPath

            # 保存当前环境变量值 (如果存在)
            $oldSkipSmudge = $env:GIT_LFS_SKIP_SMUDGE
            try
            {
                Write-Host "📦 开始处理: $($repo.description)" -ForegroundColor Cyan
                $repo_name = Split-Path $repo.url -Leaf
                $fullPath = Join-Path $COMFY_DIR "$($repo.local_path)/$repo_name"

                #格式化路径
                $gitSafePath = $fullPath -replace '\\', '/'
                # 确保驱动器号大写 (如果路径包含驱动器号)
                if ($gitSafePath -match '^[a-z]:') {
                    $gitSafePath = $gitSafePath.Substring(0, 1).ToUpper() + $gitSafePath.Substring(1)
                }

                Write-Host " 仓库路径: $gitSafePath" -ForegroundColor Cyan


                # 设置环境变量以跳过 LFS 下载
                $env:GIT_LFS_SKIP_SMUDGE = 1

                # 兼容移动硬盘运行
                #                git config --global --add safe.directory $gitSafePath
                if (Test-Path (Join-Path $fullPath ".git")) {
                    Write-Host "🔄 仓库已存在，检查目录内容..." -ForegroundColor Cyan

                    # 获取目录下所有项 (包括隐藏的)，但不递归 (-Depth 0)
                    $items = Get-ChildItem -Path $fullPath -Force -Depth 0

                    # 过滤掉 .git 目录本身 和 其他隐藏项 (名字以.开头的文件或目录)
                    $nonHiddenUserItems = $items | Where-Object { $_.Name -ne ".git" -and -not $_.Name.StartsWith(".") }

                    # 检查过滤后的列表是否为空
                    if ($nonHiddenUserItems.Count -eq 0) {

                        Write-Host "  目录仅包含 .git 或隐藏项，执行强制更新..."

                        # --- 强制更新逻辑 (fetch + reset) ---
                        Write-Host "  Fetching updates..."
                        git -C $fullPath fetch origin --force --tags --prune --progress --depth=1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "❌ Fetch 失败: $($repo.description)，Git 退出码: $LASTEXITCODE" -ForegroundColor Red
                            continue
                        }

                        # 检查是否存在 index.lock 文件
                        # 检查是否存在 index.lock 文件
                        $lockFilePath = Join-Path $fullPath ".git/index.lock"
                        if (Test-Path $lockFilePath) {
                            Write-Host "⚠️ 检测到锁文件 ($lockFilePath)。这可能表示另一个 Git 进程正在运行，或者上次操作异常终止。" -ForegroundColor Yellow
                            Write-Host "⚠️ 尝试强制删除锁文件以继续更新... (风险提示：如果存在其他活动进程，可能导致仓库损坏)" -ForegroundColor Yellow
                            try {
                                Remove-Item -Path $lockFilePath -Force -ErrorAction Stop
                                Write-Host "  锁文件已删除。" -ForegroundColor Green
                            } catch {
                                Write-Host "❌ 无法删除锁文件 ($lockFilePath): $_" -ForegroundColor Red
                                Write-Host "  跳过更新: $($repo.description)" -ForegroundColor Red
                                continue # 如果无法删除锁文件，则跳过此仓库
                            }
                        }

                        $remoteBranch = "origin/main" # Or origin/master, etc.
                        Write-Host "  Attempting to reset local state to $remoteBranch..." # 修改日志
                        git -C $fullPath reset --hard $remoteBranch
                        $resetExitCode = $LASTEXITCODE # 立刻保存退出码
                        Write-Host "  Reset command finished with exit code: $resetExitCode" # 增加结束日志

                        if ($resetExitCode -ne 0) {
                            Write-Host "❌ Reset 失败: $($repo.description)，Git 退出码: $resetExitCode" -ForegroundColor Red
                            continue
                        }

                    }
                } else {
                    Write-Host "📦 克隆仓库..." -ForegroundColor Cyan

                    # 直接使用带过滤条件的clone命令
                    git clone --filter=blob:none --no-checkout $repo.url $fullPath
                    git -C $fullPath sparse-checkout init --cone
                    git -C $fullPath sparse-checkout set "/*" "!*.safetensors" "!*.ckpt" "!*.bin" "!*.pth" "!*.pt" "!*.onnx" "!*.pkl"
                    git -C $fullPath checkout

                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "❌ 克隆失败: $($repo.description)" -ForegroundColor Red
                        continue
                    }
                }

                if ($LASTEXITCODE -eq 0) {
                    # 获取需要下载的大文件列表（从 .gitattributes 中提取）
                    Write-Host "� 解析需要下载的大文件列表..." -ForegroundColor Cyan
                    $lfsFiles = @()
                    if (Test-Path ".gitattributes") {
                        $lfsFiles = Get-Content ".gitattributes" | Where-Object {
                            $_ -match '^([^\s#]+).*filter=lfs'
                        } | ForEach-Object {
                            $filePattern = $Matches[1]
                            # 获取实际匹配的文件
                            git ls-files $filePattern
                        }
                    }

                    foreach ($file in $lfsFiles) {
                        Write-Host "处理文件: $file"
                        $filePath = Join-Path $fullPath $file

                        # 构建文件下载 URL
                        $file_url = "$($repo.url)/resolve/main/$file"
                        Write-Host "� 开始下载文件: $file" -ForegroundColor Cyan
                        Write-Host "� 下载URL: $file_url" -ForegroundColor Cyan

                        $params = @{
                            URL = $file_url
                            DOWNLOAD_DIR = $fullPath
                            FILENAME = $file
                        }
                        if($HF_TOKEN){
                            $params.HEADER = "Authorization: Bearer $HF_TOKEN"
                        }

                        # 调用工具函数下载模型
                        Start-FileDownloadWithAria2 @params
                        Write-Host "-------------------"
                    }

                    Write-Host "✅ 完成: $($repo.description)" -ForegroundColor Green
                } else {
                    Write-Host "❌ 克隆失败: $($repo.description)" -ForegroundColor Red
                }

                Pop-Location
            }
            finally
            {
                # 确保无论如何都会返回到原始目录
                Set-Location $previousLocation
                # 恢复环境变量
                if ($null -ne $oldSkipSmudge) {
                    $env:GIT_LFS_SKIP_SMUDGE = $oldSkipSmudge
                    Write-Host "  恢复 GIT_LFS_SKIP_SMUDGE 环境变量。" -ForegroundColor Gray
                } else {
                    # 如果之前不存在，则移除
                    Remove-Item Env:\GIT_LFS_SKIP_SMUDGE -ErrorAction SilentlyContinue
                    Write-Host "  移除临时设置的 GIT_LFS_SKIP_SMUDGE 环境变量。" -ForegroundColor Gray
                }
            }

            Write-Host "-------------------"
        }

        Write-Host "✨ 所有任务处理完成" -ForegroundColor Green
        if ($isInteractive) {
            Write-Host "`n按 Enter 键退出..." -ForegroundColor Cyan
            do {
                $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            } until ($key.VirtualKeyCode -eq 13) # 13 是 Enter 键的虚拟键码
        }
    }
}


