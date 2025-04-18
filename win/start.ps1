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

function Start-ComfyUIWithLogging {
    param(
        [string]$condaPythonPath,
        [string]$COMFY_DIR,
        [int]$PORT
    )

    # 创建临时日志文件
    $logFile = [System.IO.Path]::GetTempFileName()
    $errorLogFile = [System.IO.Path]::GetTempFileName()

    # 启动进程并捕获所有输出
    $process = Start-Process -FilePath $condaPythonPath `
        -ArgumentList "$COMFY_DIR/main.py", "--listen", "0.0.0.0", "--port", "$PORT" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $logFile `
        -RedirectStandardError $errorLogFile

    $startTime = Get-Date
    $serverStarted = $false
    $lastPosition = 0
    $lastErrorPosition = 0

    while (-not $serverStarted) {
        # 读取标准输出新增内容
        $stream = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Position = $lastPosition
        $reader = New-Object System.IO.StreamReader($stream)
        $newContent = $reader.ReadToEnd()
        $lastPosition = $stream.Position
        $reader.Close()
        $stream.Close()

        # 读取错误输出新增内容
        $errorStream = [System.IO.File]::Open($errorLogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $errorStream.Position = $lastErrorPosition
        $errorReader = New-Object System.IO.StreamReader($errorStream)
        $newErrorContent = $errorReader.ReadToEnd()
        $lastErrorPosition = $errorStream.Position
        $errorReader.Close()
        $errorStream.Close()

        # 打印新增日志
        if ($newContent) {
            Write-Host $newContent -NoNewline
        }
        if ($newErrorContent) {
            Write-Host $newErrorContent -NoNewline
        }

        # 检查是否启动成功
        if ($newContent -match "To see the GUI go to: http" -or $newErrorContent -match "To see the GUI go to: http") {
            $serverStarted = $true
            Start-Sleep -Seconds 2
            # 在检测到服务器启动后添加端口检查
            if ($serverStarted) {
                # 添加端口可用性检查
                $portAvailable = Test-NetConnection -ComputerName localhost -Port $PORT -InformationLevel Quiet
                if (-not $portAvailable) {
                    Write-Host "端口 $PORT 不可用，请检查防火墙设置" -ForegroundColor Red
                    exit 1
                }

                # 尝试多种浏览器打开方式
                try {
                    # 方法1：直接打开
                    Start-Process "http://localhost:$PORT"
                } catch {
                    try {
                        # 方法2：通过默认浏览器打开
                        Start-Process "open" -ArgumentList "http://localhost:$PORT"
                    } catch {
                        Write-Host "无法自动打开浏览器，请手动访问: http://localhost:$PORT" -ForegroundColor Yellow
                    }
                }
            }
            break
        }

        Start-Sleep -Milliseconds 100
    }

    # 清理临时文件
    Remove-Item $logFile -ErrorAction SilentlyContinue
    Remove-Item $errorLogFile -ErrorAction SilentlyContinue

    return $process
}

Write-Host "正在启动 ComfyUI" -ForegroundColor Green

# 创建日志文件
$logFile = "comfy.log"
$errorLogFile = "comfy_error.log"
New-Item -Path $logFile -ItemType File -Force | Out-Null
New-Item -Path $errorLogFile -ItemType File -Force | Out-Null

Write-Host "创建日志文件完成" -ForegroundColor Cyan

# 启动进程并捕获所有输出
$process = Start-Process -FilePath $condaPythonPath `
    -ArgumentList "$COMFY_DIR\main.py", "--listen", "0.0.0.0", "--port", "$PORT" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $errorLogFile

Write-Host "进程已启动，开始监控日志..." -ForegroundColor Cyan

$serverStarted = $false

# 在循环前添加变量记录已处理日志行数
$processedLines = 0

while (-not $serverStarted) {
    # 读取标准输出和错误输出
    $stdoutContent = Get-Content $logFile -ErrorAction SilentlyContinue
    $stderrContent = Get-Content $errorLogFile -ErrorAction SilentlyContinue

    # 合并两个输出
    $allContent = @()
    if ($stdoutContent) { $allContent += $stdoutContent }
    if ($stderrContent) { $allContent += $stderrContent }

    # 只处理新增的行
    if ($allContent.Count -gt $processedLines) {
        for ($i = $processedLines; $i -lt $allContent.Count; $i++) {
            $line = $allContent[$i]
            Write-Host "$line"

            if ($line -match "To see the GUI go to: http") {
                $serverStarted = $true
                Write-Host "检测到服务器启动成功" -ForegroundColor Green
                Start-Sleep -Seconds 2

                try {
                    Write-Host "尝试打开浏览器..." -ForegroundColor Cyan
                    Start-Process "http://localhost:$PORT"
                    Write-Host "浏览器启动成功" -ForegroundColor Green
                } catch {
                    Write-Host "打开浏览器失败: $_" -ForegroundColor Red
                }
                break
            }
        }
        $processedLines = $allContent.Count
    }

    if (-not $serverStarted) {
        Start-Sleep -Milliseconds 500
    }
}
# 清理日志文件
Remove-Item $logFile -ErrorAction SilentlyContinue
Remove-Item $errorLogFile -ErrorAction SilentlyContinue

# 等待进程结束
$process | Wait-Process