
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 函数：显示使用方法
function Show-Usage {
    Write-Host "使用方法: $($MyInvocation.MyCommand.Name) <HF下载token>"
    Write-Host "示例: $($MyInvocation.MyCommand.Name) 'dfd44121xxxxxxx'"
}

$ROOT_DIR = $PSScriptRoot
$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"
$HF_TOKEN = ""
# 导入TOML解析函数
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "parse_toml.ps1")

#  引入工具函数
. (Join-Path $ROOT_DIR "tools.ps1")


# 调用函数
Install-HuggingfaceRepos -isInteractive $true






