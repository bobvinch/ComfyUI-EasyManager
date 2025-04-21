
# 设置Conda路径
$CONDA_PATH = "C:\Users\$env:USERNAME\miniconda3"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
$ROOT_DIR = $PSScriptRoot

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
