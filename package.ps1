param([string]$Version = "0.1.0-beta")

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$releaseRoot = Join-Path $projectRoot "release"
$folderName = "WarThunderTripleScreen-v$Version"
$staging = Join-Path $releaseRoot $folderName
$archive = Join-Path $releaseRoot "$folderName.zip"

$files = @(
    "WarThunderTripleScreen.ps1",
    "WarThunderTripleScreen.ini",
    "Run-WarThunderTripleScreen.cmd",
    "Fix-Current-WarThunder-Window.cmd",
    "README.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "LICENSE"
)

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
New-Item -ItemType Directory -Path $staging | Out-Null

foreach ($file in $files) {
    $source = Join-Path $projectRoot $file
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing release file: $file" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $staging $file)
}

Compress-Archive -LiteralPath $staging -DestinationPath $archive -CompressionLevel Optimal
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $archive
Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $archive))
Write-Output "Created $archive"
Write-Output "SHA-256 $($hash.Hash)"

