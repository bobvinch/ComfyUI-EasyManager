
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 导入TOML解析函数
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "parse_toml.ps1")

# 设置镜像源
Write-Host "🚀 设置默认镜像源为阿里云镜像..." -ForegroundColor Cyan
$PIP_MIRROR = "https://mirrors.aliyun.com/pypi/simple/"
$configFile = Join-Path $ROOT_DIR "config.toml"
$config = Convert-FromToml $configFile
# 配置pip镜像源
if ($config.resources -and $config.resources.pip_mirror) {
    Write-Host "🔧 检测到配置的pip镜像源，正在设置: $($config.resources.pip_mirror)" -ForegroundColor Cyan
    & $condaPipPath config set global.index-url $config.resources.pip_mirror
    $PIP_MIRROR = $config.resources.pip_mirror
} else {
    Write-Host "ℹ️ 未配置pip镜像源，使用默认源:$PIP_MIRROR" -ForegroundColor Yellow
}
$ROOT_DIR = $PSScriptRoot
$envPath = Join-Path $ROOT_DIR "envs\comfyui"
$COMFY_DIR = Join-Path $ROOT_DIR "ComfyUI"
$target = "$envPath\Lib\site-packages"

# 定义依赖安装函数
function Install-Requirements {
    param (
        [string]$ReqFile,
        [string]$Context
    )

    if (-not (Test-Path $ReqFile)) {
        Write-Host "⚠️ 未找到依赖文件: $ReqFile" -ForegroundColor Yellow
        return $false
    }

    Write-Host "📦 检查${Context}依赖..." -ForegroundColor Cyan

    # 获取已安装的包列表
    Write-Host "🔍 获取已安装包列表..." -ForegroundColor Cyan
    $installedPackages = @{}
    $condaPipPath = "$envPath\Scripts\pip.exe"
    & $condaPipPath list --format=freeze | ForEach-Object {
        if ($_ -match '^([^=]+)==.*$') {
            $installedPackages[$Matches[1]] = $true
        }
    }

    # 创建需要安装的包列表
    $toInstall = @()

    # 读取requirements文件
    Get-Content $ReqFile | ForEach-Object {
        $package = $_.Trim()
        
        # 跳过空行和注释行
        if ($package -and -not $package.StartsWith("#")) {
            # 提取包名
            if ($package -match '^([^=>< ]+)') {
                $pkgName = $Matches[1]
                
                if ($installedPackages.ContainsKey($pkgName)) {
                    Write-Host "✅ $pkgName 已安装，跳过" -ForegroundColor Green
                } else {
                    Write-Host "📝 添加 $pkgName 到安装列表" -ForegroundColor Cyan
                    $toInstall += $package
                }
            }
        }
    }

    # 定义要排除的包名，torch相关的包通过conda管理，避免其他包被误安装
    $excludePackages = @(
        'torch',
        'torchvision',
        'torchaudio'
    )

    # 过滤torch相关的包和版本控制
    $toInstall = $toInstall | ForEach-Object {
        $package = $_
        # 去除 Python 版本约束后缀 (如 package>=3.6)
        $packageName = ($package -split '[<>=]')[0].Trim()

        # 检查是否是需要排除的包
        if ($excludePackages | Where-Object { $packageName -like "*$_*" }) {
            return $null
        }

        # 检查是否在 TOML 配置中有指定版本
        $configVersion = $config.packages.$packageName
        if ($configVersion) {
            # 使用配置文件中指定的版本
            return $configVersion
            Write-Host "📝 包强制版本控制，添加 $packageName 到安装列表" -ForegroundColor Cyan
        }
        # 如果没有在配置中指定版本，使用原始包名
        return $package
    } | Where-Object { $_ -ne $null }


    # 批量安装未安装的包
    if ($toInstall.Count -gt 0) {
        # 过滤掉 PyTorch 相关的包
        $toInstall = $toInstall | Where-Object {
            $_ -notmatch 'torch|torchvision|torchaudio'
        }

        if ($toInstall.Count -gt 0) {
            Write-Host "� 开始安装缺失的依赖..." -ForegroundColor Cyan
            $total = $toInstall.Count
            $current = 0
            try {
                if ($PIP_MIRROR) {
                    # 使用自定义镜像源
                    $toInstall | ForEach-Object {
                        $current++
                        $percent = [math]::Round(($current / $total) * 100, 1)
                        Write-Host "[$current/$total] ($percent%) 正在安装: $_" -ForegroundColor Yellow
                        & $condaPipPath install -i $PIP_MIRROR $_ --target "$envPath\Lib\site-packages" --progress-bar on
                        Write-Host ""  # 添加空行以提高可读性
                    }
                } else {
                    # 使用默认镜像源
                    $toInstall | ForEach-Object {
                        $current++
                        $percent = [math]::Round(($current / $total) * 100, 1)
                        Write-Host "[$current/$total] ($percent%) 正在安装: $_" -ForegroundColor Yellow
                        & $condaPipPath install $_ --target "$envPath\Lib\site-packages" --no-cache-dir --progress-bar on
                        Write-Host ""  # 添加空行以提高可读性
                    }
                }
                Write-Host "✅ 所有依赖安装完成" -ForegroundColor Green
            } catch {
                Write-Host "❌ 部分依赖安装失败: $_" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "✅ 无需安装其他依赖" -ForegroundColor Green
        }
    }

    Write-Host "✅ ${Context}依赖检查完成" -ForegroundColor Green
    return $true
}

function Get-CondaPackageInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$EnvPath,

        [Parameter(Mandatory=$true)]
        [string]$PackageName
    )

    try {
        # 使用 pip show 获取详细包信息
        $packageInfo = & $condaPipPath show $PackageName --target $EnvPath 2>$null

        if ($LASTEXITCODE -eq 0 -and $packageInfo) {
            # 提取版本信息
            $versionLine = $packageInfo | Select-String "^Version:\s*(.+)$"
            $version = if ($versionLine) {
                $versionLine.Matches.Groups[1].Value.Trim()
            } else {
                $null
            }

            return @{
                IsInstalled = $true
                Version = $version
                BuildString = $null
                Channel = $null
            }
        } else {
            return @{
                IsInstalled = $false
                Version = $null
                BuildString = $null
                Channel = $null
            }
        }
    }
    catch {
        Write-Host "❌ 获取包信息时出错: $_" -ForegroundColor Red
        return @{
            IsInstalled = $false
            Version = $null
            BuildString = $null
            Channel = $null
        }
    }
}

# 从numpy == 1.36.4 字符串中提取包名和版本号
function Get-PackageVersionInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$VersionString
    )

    try {
        # 清理输入字符串
        $VersionString = $VersionString.Trim()

        # 匹配版本号和操作符（支持操作符前后可选的空格）
        if ($VersionString -match "(\S+)\s*([<>=]=?)\s*(\S+)") {
            return @{
                PackageName = $Matches[1].Trim()    # 包名并清理空格
                Operator = $Matches[2].Trim()       # 操作符并清理空格
                Version = $Matches[3].Trim()        # 版本号并清理空格
                Success = $true
            }
        }

        # 如果没有匹配到操作符，返回原始包名
        return @{
            PackageName = $VersionString
            Operator = $null
            Version = $null
            Success = $false
        }
    }
    catch {
        Write-Host "❌ 版本字符串解析失败: $_" -ForegroundColor Red
        return $null
    }
}

# 版本比较函数
function Compare-Versions {
    param (
        [string]$Version1,
        [string]$Version2
    )

    try {
        # 提取纯数字版本部分
        $v1Numbers = ($Version1 -split '[a-zA-Z]')[0]
        $v2Numbers = ($Version2 -split '[a-zA-Z]')[0]

        # 转换为版本对象
        $v1 = [System.Version]$v1Numbers
        $v2 = [System.Version]$v2Numbers

        # 如果数字部分相同，比较后缀
        if ($v1 -eq $v2) {
            $v1Suffix = ($Version1 -replace '[0-9\.]', '').ToLower()
            $v2Suffix = ($Version2 -replace '[0-9\.]', '').ToLower()

            # 处理后缀比较（rc < '' < beta < alpha）
            $suffixOrder = @{
                'rc' = 3
                '' = 4
                'b' = 1
                'beta' = 1
                'a' = 0
                'alpha' = 0
            }

            $v1Value = $suffixOrder[$v1Suffix]
            $v2Value = $suffixOrder[$v2Suffix]

            return $v1Value.CompareTo($v2Value)
        }

        # 返回数字版本的比较结果
        return $v1.CompareTo($v2)
    }
    catch {
        Write-Host "❌ 版本比较失败: $_" -ForegroundColor Red
        return 0
    }
}

function Test-PackageUpgradeNeeded {
    param (
        [Parameter(Mandatory=$true)]
        [string]$VersionRequirement,

        [Parameter(Mandatory=$true)]
        [string]$CurrentVersion
    )

    try {
        # 清理版本字符串
        $VersionRequirement = $VersionRequirement.Trim()
        $CurrentVersion = $CurrentVersion.Trim()


        # 修改正则表达式，使用非贪婪匹配并明确指定操作符
        if ($VersionRequirement -match "(\S+?)\s*(==|>=|<=|>|<)\s*(\S+)") {
            $packageName = $Matches[1].Trim()
            $operator = $Matches[2].Trim()
            $requiredVersion = $Matches[3].Trim()


            $compareResult = Compare-Versions $CurrentVersion $requiredVersion

            $needUpgrade = switch ($operator) {
                "==" { $compareResult -ne 0 }    # 不相等时需要更新
                ">=" { $compareResult -lt 0 }    # 当前版本小于要求版本时需要更新
                "<=" { $compareResult -gt 0 }    # 当前版本大于要求版本时需要更新
                ">" { $compareResult -le 0 }     # 当前版本小于等于要求版本时需要更新
                "<" { $compareResult -ge 0 }     # 当前版本大于等于要求版本时需要更新
            }
            return $needUpgrade
        }
        # 如果没有操作符，且当前版本不为空，则不需要升级
        elseif ($CurrentVersion) {
            return $false
        }
        # 如果没有操作符，且当前版本为空，则需要安装
        else {
            return $true
        }
    }
    catch {
        Write-Host "❌ 版本比较出错: $_" -ForegroundColor Red
        return $false
    }
}



# 安装ComfyUI环境依赖
Write-Host "🚀 开始安装ComfyUI环境依赖" -ForegroundColor Cyan
try {
    # 检查ComfyUI目录是否存在
    if (-not (Test-Path $COMFY_DIR)) {
        Write-Host "❌ ComfyUI目录不存在: $COMFY_DIR" -ForegroundColor Red
        exit 1
    }

    # 切换到ComfyUI目录
    Set-Location $COMFY_DIR -ErrorAction Stop
    Write-Host "📂 工作目录已切换到: $COMFY_DIR" -ForegroundColor Green

    # 检查requirements文件
    $requirements_file = Join-Path $COMFY_DIR "requirements.txt"

    # 直接调用函数
    Install-Requirements -ReqFile $requirements_file -Context "ComfyUI"

    if (-not $?) {
        Write-Host "❌ 依赖安装失败" -ForegroundColor Red
        exit 1
    }

    Write-Host "✅ ComfyUI依赖安装完成" -ForegroundColor Green


    # 处理自定义节点
    Push-Location (Join-Path $COMFY_DIR "custom_nodes")
    Write-Host "📂 进入自定义节点目录: $(Get-Location)" -ForegroundColor Green

    # 使用Convert-FromToml函数解析TOML文件
    $reposFile = Join-Path $ROOT_DIR "repos.toml"
    if (-not (Test-Path $reposFile)) {
        Write-Host "❌ 仓库配置文件不存在: $reposFile" -ForegroundColor Red
        exit 1
    }

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

    #将packages里的包，全部添加到toInstall中
    if ($config.packages) {
        $config.packages | Get-Member -MemberType NoteProperty | ForEach-Object {
            $packageName = $_.Name
            $versionString = $config.packages.$packageName
            #判断是否已经安装和安装的版本是否一致
            $isInstalled =$false
            $versionOld = ''
            try
            {
                $installedInfo = & $condaPipPath show $packageName 2>$null
                $installedVersion = ($installedInfo | Select-String "^Version:\s*(.+)$").Matches.Groups[1].Value
                if ($installedVersion) {
                    $isInstalled = $true
                    $versionOld = $installedVersion
                }
                else {
                    $isInstalled = $false
                }
            }
            catch
            {
                $isInstalled = $false
            }

            Write-Host "📦 包信息: "$packageName"安装状态：" $isInstalled

            if ($versionString) {
                # version格式是sympy==1.13.1或者sympy>=1.13.1格式，需要处理获取纯的版本号
                $versionObj = Get-PackageVersionInfo -VersionString $versionString
                $versionNew = $versionObj.Version
                $needUpdate =Test-PackageUpgradeNeeded -CurrentVersion $versionOld -VersionRequirement $versionString

                if($isInstalled -and -not $needUpdate){
                    Write-Host "📦 包已经安装，且版本一致，跳过安装: 包名: $packageName, 版本: $versionNew" -ForegroundColor Green
                    return
                }
                # 强制更新
                Write-Host "📦 正在强制更新安装包: 包名: $packageName,旧版本:$versionOld, 新版本: $versionNew" -ForegroundColor Yellow
                & $condaPipPath uninstall $packageName --yes
                & $condaPipPath install $versionString --target $target --force-reinstall --upgrade --no-cache-dir --progress-bar on
            } else {
                if($isInstalled){
                    Write-Host "📦 包已经安装，跳过安装: 包名: $packageName" -ForegroundColor Green
                    return
                }
                Write-Host "📦 正在安装包: 包名: $packageName" -ForegroundColor Yellow
                & $condaPipPath install $packageName --target $target --force-reinstall --upgrade --no-cache-dir --progress-bar on
            }
        }
    }
    Write-Host "✅ 依赖安装完成" -ForegroundColor Green


}
catch {
    Write-Host "❌ 安装过程中发生错误: $_" -ForegroundColor Red
    exit 1
}