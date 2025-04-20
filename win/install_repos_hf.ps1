
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 函数：显示使用方法
function Show-Usage {
    Write-Host "使用方法: $($MyInvocation.MyCommand.Name) <HF下载token>"
    Write-Host "示例: $($MyInvocation.MyCommand.Name) 'dfd44121xxxxxxx'"
}


# 导入TOML解析函数
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "parse_toml.ps1")

# 获取脚本所在目录
$ROOT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "脚本所在目录是: $ROOT_DIR"
$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"
$HF_TOKEN = $args[0]

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
    # 检查并安装必要工具
    foreach ($tool in $tools.Keys) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Host "⚙️ 安装 $tool..." -ForegroundColor Cyan
            & $tools[$tool]
        }
    }

    $repos = Convert-FromToml $REPOS_FILE

    # 配置 git 凭证
    git config --global credential.helper store
    git config --global init.defaultBranch main
    "https://USER:${HF_TOKEN}@huggingface.co" | Out-File -FilePath (Join-Path $HOME ".git-credentials")


    foreach ($repo in $repos.repos) {
        Write-Host "📦 开始处理: $($repo.description)" -ForegroundColor Cyan
        $repo_name = Split-Path $repo.url -Leaf
        $fullPath = Join-Path $COMFY_DIR "$($repo.local_path)/$repo_name"

        # 创建目标目录
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null

        # 保存当前目录
        $previousLocation = Get-Location
        Set-Location $fullPath
        try
        {
            if (Test-Path ".git") {
                Write-Host "� 仓库已存在，检查更新..." -ForegroundColor Cyan
            } else {
                Write-Host "📦 开始处理: $($repo.description)" -ForegroundColor Cyan
                $repo_name = Split-Path $repo.url -Leaf
                $fullPath = Join-Path $COMFY_DIR "$($repo.local_path)/$repo_name"

                if (Test-Path (Join-Path $fullPath ".git")) {
                    Write-Host "📦 仓库已存在，跳过克隆..." -ForegroundColor Cyan
                } else {
                    Write-Host "📦 克隆仓库..." -ForegroundColor Cyan
                    $env:GIT_LFS_SKIP_SMUDGE = 1

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

                    # 使用 aria2c 下载
                    & "$ROOT_DIR\download.ps1" $file_url $file "Authorization: Bearer $HF_TOKEN" $fullPath
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
        }

        Write-Host "-------------------"
    }

    Write-Host "✨ 所有任务处理完成" -ForegroundColor Green
}
