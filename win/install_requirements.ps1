
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 导入TOML解析函数
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "parse_toml.ps1")

# 设置镜像源
Write-Host "🚀 设置默认镜像源为阿里云镜像..." -ForegroundColor Cyan
$PIP_MIRROR = "https://mirrors.aliyun.com/pypi/simple/"
$ENV_PATH = Join-Path $ROOT_DIR "envs\comfyui"
$configFile = Join-Path $ROOT_DIR "config.toml"

if(Test-Path $configFile){
    $config = Convert-FromToml $configFile
    # 配置pip镜像源
    if ($config.resources -and $config.resources.pip_mirror) {
        Write-Host "🔧 检测到配置的pip镜像源，正在设置: $($config.resources.pip_mirror)" -ForegroundColor Cyan
        & $condaPipPath config set global.index-url $config.resources.pip_mirror
        $PIP_MIRROR = $config.resources.pip_mirror
    } else {
        Write-Host "ℹ️ 未配置pip镜像源，使用默认源:$PIP_MIRROR" -ForegroundColor Yellow
    }
}
else
{
    Write-Host "ℹ️ 未找到配置文件: $configFile" -ForegroundColor Yellow
}


$condaPipPath = "$ENV_PATH\Scripts\pip.exe"
$condaPythonPath = "$ENV_PATH\python.exe"

$ROOT_DIR = $PSScriptRoot
$envPath = Join-Path $ROOT_DIR "envs\comfyui"
$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"
$CONDA_PATH = "C:\Users\$env:USERNAME\miniconda3"

# 自动检测代理
$proxyEnabled = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyEnable
$sysProxy = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyServer

if ($proxyEnabled -eq 1 -and $sysProxy) {
    $env:http_proxy = "http://$sysProxy"
    $env:https_proxy = "http://$sysProxy"
    Write-Host "✅ 已启用系统代理: http://$sysProxy" -ForegroundColor Green
} elseif (-not $proxyEnabled) {
    Write-Host "⚠️ 系统代理未启用" -ForegroundColor Yellow
} else {
    Write-Host "⚠️ 未检测到有效的代理设置" -ForegroundColor Yellow
}

#  引入工具函数
. (Join-Path $ROOT_DIR "tools.ps1")


# 安装ComfyUI环境依赖
Write-Host "🚀 开始安装ComfyUI环境依赖" -ForegroundColor Cyan
try {
    # 检查ComfyUI目录是否存在
    if (-not (Test-Path $COMFY_DIR)) {
        Write-Host "❌ ComfyUI目录不存在: $COMFY_DIR" -ForegroundColor Red
        exit 1
    }
    # 初始化Conda和Python环境
    Install-CondaPythonEnvironment

    # 初始化pytorch
    ./init_pytorch.ps1

    # 切换到ComfyUI目录
    Set-Location $COMFY_DIR -ErrorAction Stop
    Write-Host "📂 工作目录已切换到: $COMFY_DIR" -ForegroundColor Green

    # 检查requirements文件
    $requirements_file = Join-Path $COMFY_DIR "requirements.txt"

    # 直接调用函数
    Install-Requirements -ReqFile $requirements_file -Context "ComfyUI"

    if (-not $?) {
        Write-Host "❌ 依赖安装失败" -ForegroundColor Red
    }

    Write-Host "✅ ComfyUI依赖安装完成" -ForegroundColor Green


    # 处理自定义节点
    Push-Location (Join-Path $COMFY_DIR "custom_nodes")
    Write-Host "📂 进入自定义节点目录: $(Get-Location)" -ForegroundColor Green

    # 使用Convert-FromToml函数解析TOML文件
    $reposFile = Join-Path $ROOT_DIR "repos.toml"
    if (-not (Test-Path $reposFile)) {
        Write-Host "❌ 仓库配置文件不存在: $reposFile" -ForegroundColor Red
    }
    else
    {
        $repos = Convert-FromToml $reposFile
        Write-Host "🔍 共发现 $($repos.repos.Count) 个自定义节点需要处理" -ForegroundColor Cyan
        # 安装仓库和依赖
        foreach ($repo in $repos.repos) {
            # 移除 .git 后缀获取仓库名
            $repoName = Split-Path $repo.url -Leaf
            $repoName = $repoName -replace '\.git$', ''

            Write-Host "🔄 安装节点依赖: $repoName" -ForegroundColor Cyan

            # 克隆仓库
            if (-not (Test-Path $repoName)) {
                try {
                    git clone $repo.url
                    if ($LASTEXITCODE -ne 0) {
                        throw "仓库克隆失败: $repoName"
                    }
                    Write-Host "✅ 仓库克隆成功: $repoName" -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ 仓库克隆失败: $repoName" -ForegroundColor Red
                    Write-Host "错误详情: $_" -ForegroundColor Red
                    continue  # 跳过当前仓库继续处理下一个
                }
            }

            # 安装依赖
            $reqFile = Join-Path $repoName "requirements.txt"
            if (Test-Path $reqFile) {
                try {
                    Install-Requirements -ReqFile $reqFile -Context "$repoName 插件"
                    if (-not $?) {
                        Write-Host "⚠️ 插件依赖安装可能存在问题: $repoName" -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "❌ 插件依赖安装失败: $repoName" -ForegroundColor Red
                    Write-Host "错误详情: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "ℹ️ 未找到依赖文件，跳过: $repoName" -ForegroundColor Gray
            }
        }
    }


    # 安装自定义节点依赖
    Install-CustomNodeRequirements

    # 检查依赖冲突
    Test-DependencyConflicts

    # 安装自定义依赖
    Install-UserDefinedRequirements


    Write-Host "✅ 依赖安装完成" -ForegroundColor Green


}
catch {
    Write-Host "❌ 安装过程中发生错误: $_" -ForegroundColor Red
    throw
}