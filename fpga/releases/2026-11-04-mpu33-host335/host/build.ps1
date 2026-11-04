param([string]$Python="python")
$ErrorActionPreference="Stop"
& $Python -m PyInstaller --noconfirm --distpath (Join-Path $PSScriptRoot "dist") --workpath (Join-Path $PSScriptRoot "build-output") (Join-Path $PSScriptRoot "TangLab335.spec")
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
