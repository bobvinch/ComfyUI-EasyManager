$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8


$ROOT_DIR = $PSScriptRoot

#  引入工具函数
. (Join-Path $ROOT_DIR "tools.ps1")
# 引入TOML解析函数
. (Join-Path $ROOT_DIR "parse_toml.ps1")

# 函数：显示使用方法
function Show-Usage {
    Write-Host "使用方法: $($MyInvocation.MyCommand.Name) <下载链接> [文件名] <认证头> <下载目录>"
    Write-Host "示例: $($MyInvocation.MyCommand.Name) 'https://example.com/model.safetensors' 'custom_name.safetensors' 'Authorization: Bearer xxx' '/path/to/download'"
}


function Start_DownloadUserConfigModels {
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
        $HF_TOKEN = ""
        $config = Get-ConfigFromFile
        if ($config.authorizations -and $config.authorizations.huggingface_token) {
            $HF_TOKEN = $config.authorizations.huggingface_token
            Write-Host "🔧 检测到配置的huggingface token，已经设置: $($config.authorizations.huggingface_token)" -ForegroundColor Cyan
        } else {
            Write-Host "ℹ️ 未配置huggingface token，部分资源可能无效下载" -ForegroundColor Yellow
        }


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
            Start-FileDownload @params
        }
    }
    else
    {
        Write-Host "未找到模型配置，跳过下载" -ForegroundColor Yellow
    }
}

Start_DownloadUserConfigModels

