$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 函数：显示使用方法
function Show-Usage {
    Write-Host "使用方法: $($MyInvocation.MyCommand.Name) <下载链接> [文件名] <认证头> <下载目录>"
    Write-Host "示例: $($MyInvocation.MyCommand.Name) 'https://example.com/model.safetensors' 'custom_name.safetensors' 'Authorization: Bearer xxx' '/path/to/download'"
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
Install_Aria2


# 检查参数数量
if ($args.Count -lt 3) {
    Write-Host "❌ 参数不足" -ForegroundColor Red
    Show-Usage
    exit 1
}

# 解析参数
$URL = $args[0]
$HEADER = $null
$DOWNLOAD_DIR = $null
$FILENAME = $null

# 根据参数数量处理不同情况
if ($args.Count -eq 3) {
    # 从URL中提取文件名
    $FILENAME = ([System.Uri]$URL).Segments[-1].Split('?')[0]
    $HEADER = $args[1]
    $DOWNLOAD_DIR = $args[2]
} else {
    $FILENAME = $args[1]
    $HEADER = $args[2]
    $DOWNLOAD_DIR = $args[3]
}

Write-Host "解析参数，下载地址：URL: $URL, 文件名：$FILENAME, 认证头：$HEADER, 下载目录：$DOWNLOAD_DIR"

# 检查下载目录是否存在，不存在则创建
if (-not (Test-Path $DOWNLOAD_DIR)) {
    Write-Host "🔄 创建下载目录: $DOWNLOAD_DIR" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $DOWNLOAD_DIR -Force | Out-Null
}

# 完整的下载路径
$FULL_PATH = Join-Path $DOWNLOAD_DIR $FILENAME

Write-Host "🔄 开始下载..." -ForegroundColor Cyan
Write-Host "🔄 下载链接: $URL" -ForegroundColor Cyan
Write-Host "🔄 保存为: $FULL_PATH" -ForegroundColor Cyan

# 检查文件是否已存在
if (Test-Path $FULL_PATH) {
    # 检查是否是Git LFS占位文件（通常小于200字节）
    $fileSize = (Get-Item $FULL_PATH).Length
    if ($fileSize -lt 200) {
        Write-Host "⚠️ 发现Git LFS占位文件，删除并重新下载: $FULL_PATH" -ForegroundColor Yellow
        Remove-Item $FULL_PATH -Force
    } else {
        Write-Host "⚠️ 文件已存在，跳过下载: $FULL_PATH" -ForegroundColor Yellow
        exit 0
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
    } else {
        Write-Host "❌ 下载失败" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ 下载失败: $_" -ForegroundColor Red
    exit 1
}