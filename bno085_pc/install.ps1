$ErrorActionPreference = 'Stop'
$pythonExe = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'
if (!(Test-Path -LiteralPath $pythonExe)) { $pythonExe = (Get-Command python -ErrorAction Stop).Source }
& $pythonExe -m pip install --disable-pip-version-check --target (Join-Path $PSScriptRoot 'vendor') -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
