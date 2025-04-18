$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 函数：显示使用方法
function Show-Usage {
    Write-Host "使用方法: $($MyInvocation.MyCommand.Name) <下载链接> [文件名] <认证头> <下载目录>"
    Write-Host "示例: $($MyInvocation.MyCommand.Name) 'https://example.com/model.safetensors' 'custom_name.safetensors' 'Authorization: Bearer xxx' '/path/to/download'"
}

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