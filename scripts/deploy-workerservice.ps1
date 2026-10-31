param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('qa', 'prod')]
  [string]$Environment,
  [string]$SecretsFile,
  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stackEnvironment = if ($Environment -eq 'prod') { 'production' } else { 'qa' }
$stackDirectory = Join-Path $repositoryRoot "stacks/$stackEnvironment/workerservice"
if ([string]::IsNullOrWhiteSpace($SecretsFile)) {
  $SecretsFile = Join-Path $repositoryRoot "secrets/$Environment/workerservice.env"
}
$SecretsFile = [IO.Path]::GetFullPath($SecretsFile)
if (-not (Test-Path -LiteralPath $SecretsFile -PathType Leaf)) {
  throw 'The workerservice environment file does not exist. Decrypt and configure it before deployment.'
}

$composeArguments = @('compose', '--project-directory', $stackDirectory, '--env-file', (Join-Path $stackDirectory '.env'), '--env-file', $SecretsFile, '-f', (Join-Path $stackDirectory 'docker-compose.yml'))
$configurationOutput = & docker @composeArguments config --format json 2>&1
if ($LASTEXITCODE -ne 0) {
  throw 'Worker Compose configuration failed. Check required settings in the workerservice environment file.'
}
try {
  $configuration = ($configurationOutput -join [Environment]::NewLine) | ConvertFrom-Json
} catch {
  throw 'Worker Compose returned invalid configuration. No resolved settings have been printed.'
}
$workerEnvironment = $configuration.services.workerservice.environment

function Get-WorkerSetting([string]$Name) {
  $property = $workerEnvironment.PSObject.Properties[$Name]
  if ($null -eq $property) { return '' }
  return [string]$property.Value
}

$expectedPwaUrl = if ($Environment -eq 'qa') { 'https://qapwa.mylogbook.co.za' } else { 'https://pwa.mylogbook.co.za' }
if ((Get-WorkerSetting 'EmailOptions__PwaUrl').TrimEnd('/') -ne $expectedPwaUrl) {
  throw 'EmailOptions__PwaUrl does not match the selected environment.'
}
foreach ($settingName in @('ConnectionStrings__MyLogbookDatabase', 'EmailOptions__Host', 'EmailOptions__FromAddress')) {
  $settingValue = Get-WorkerSetting $settingName
  if ([string]::IsNullOrWhiteSpace($settingValue) -or $settingValue -match '(?i)CHANGE_ME|REPLACE_ME|YOUR_') {
    throw "Configure $settingName before deployment."
  }
}
$smtpPort = 0
if (-not [int]::TryParse((Get-WorkerSetting 'EmailOptions__Port'), [ref]$smtpPort) -or $smtpPort -lt 1 -or $smtpPort -gt 65535) {
  throw 'EmailOptions__Port must be a valid TCP port.'
}
if ((Get-WorkerSetting 'EmailOptions__SkipSslCertificateValidation') -ne 'false') {
  throw 'SMTP certificate validation must remain enabled for QA and production.'
}
if (-not [string]::IsNullOrWhiteSpace((Get-WorkerSetting 'EmailOptions__Username')) -and [string]::IsNullOrWhiteSpace((Get-WorkerSetting 'EmailOptions__Password'))) {
  throw 'EmailOptions__Password is required when an SMTP username is configured.'
}

Write-Output "Validated $Environment worker configuration. No SMTP connection or message delivery has been tested."
if ($ValidateOnly) { return }

& docker network inspect --format '{{.Name}}' mylogbook_default *> $null
if ($LASTEXITCODE -ne 0) {
  throw 'The mylogbook_default network is missing. Deploy the release database stack first.'
}
& docker @composeArguments pull
if ($LASTEXITCODE -ne 0) { throw 'Worker image pull failed. Build and publish the worker pipeline, then verify registry authentication and WORKER_IMAGE_TAG.' }
& docker @composeArguments up -d --wait --wait-timeout 60
if ($LASTEXITCODE -ne 0) { throw 'Worker deployment failed. Inspect the worker logs on the deployment host.' }
Write-Output "Started $Environment worker. Request an OTP and confirm the email arrives and no Failed rows appear in system_events before accepting the release."
