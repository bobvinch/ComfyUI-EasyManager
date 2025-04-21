
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

# 调用函数
Install-HuggingfaceRepos -isInteractive $true






