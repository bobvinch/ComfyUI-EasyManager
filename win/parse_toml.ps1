$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8



$ROOT_DIR = $PSScriptRoot
$envPath = Join-Path $ROOT_DIR "envs\comfyui"
$condaPipPath = "$envPath\Scripts\pip.exe"
$condaPythonPath = "$envPath\python.exe"
function Convert-FromToml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TomlFile
    )
    # 检查并安装tomli
    try {
        $pythonCheck = & $condaPythonPath -c "import tomli" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "需要安装tomli"
        }
    } catch {
        Write-Host "📦 正在安装 tomli 包..." -ForegroundColor Yellow
        & $condaPipPath install tomli
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ tomli 包安装失败" -ForegroundColor Red
            throw "tomli 包安装失败"
        }
        Write-Host "✅ tomli 安装成功" -ForegroundColor Green
    }

    # Python脚本解析TOML
    $pythonScript = @"
import tomli
import json
import sys

with open(sys.argv[1], 'rb') as f:
    data = tomli.load(f)
print(json.dumps(data))
"@

    $tempScript = Join-Path $env:TEMP "parse_toml.py"
    $pythonScript | Out-File -Encoding utf8 $tempScript

    try {
        $jsonData = & $condaPythonPath $tempScript $TomlFile
        $result = $jsonData | ConvertFrom-Json
        return $result
    } catch {
        Write-Host "❌ TOML解析失败: $_" -ForegroundColor Red
        throw "TOML解析失败"
    } finally {
        Remove-Item $tempScript -ErrorAction SilentlyContinue
    }
}