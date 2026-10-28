Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$secretsRoot = Join-Path $PSScriptRoot '..\secrets'
$keyPath = Join-Path $secretsRoot 'mylogbook.key'
if (-not (Test-Path -Path $keyPath -PathType Leaf)) {
  throw "Missing key file: $keyPath"
}

$targets = @('qa', 'prod', 'release')
foreach ($target in $targets) {
  $envDir = Join-Path $secretsRoot $target
  if (-not (Test-Path -Path $envDir -PathType Container)) {
    Write-Warning "Missing environment folder: $envDir"
    continue
  }

  Get-ChildItem -Path $envDir -Filter *.env -File | ForEach-Object {
    $inFile = $_.FullName
    $outFile = "$inFile.enc"
    & openssl enc -aes-256-cbc -salt -pbkdf2 -in $inFile -out $outFile -pass "file:$keyPath"
  }
}
