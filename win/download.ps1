$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8


$ROOT_DIR = $PSScriptRoot

#  引入工具函数
. (Join-Path $ROOT_DIR "tools.ps1")


# 函数：显示使用方法
function Show-Usage {
    Write-Host "使用方法: $($MyInvocation.MyCommand.Name) <下载链接> [文件名] <认证头> <下载目录>"
    Write-Host "示例: $($MyInvocation.MyCommand.Name) 'https://example.com/model.safetensors' 'custom_name.safetensors' 'Authorization: Bearer xxx' '/path/to/download'"
}

# 下载用户自定义的模型
Start_DownloadUserConfigModels -isInteractive $true

