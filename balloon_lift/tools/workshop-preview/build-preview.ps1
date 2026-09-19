[CmdletBinding()]
param(
    [string]$Source,
    [string]$Output
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$workRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $workRoot 'Contents\mods\AuthenticZBalloonLift\42\poster.png'
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $workRoot 'workshop-preview.gif'
}

$nodeCandidates = @(
    (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
)
$nodeFromPath = Get-Command node.exe -ErrorAction SilentlyContinue
if ($null -ne $nodeFromPath) {
    $nodeCandidates += $nodeFromPath.Source
}
$node = $nodeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($null -eq $node) {
    throw 'Node.js was not found. Install Node.js, then run npm install in this folder.'
}

$localNodeModules = Join-Path $PSScriptRoot 'node_modules'
$codexNodeModules = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules'
if (Test-Path -LiteralPath (Join-Path $localNodeModules 'sharp')) {
    $env:NODE_PATH = $localNodeModules
} elseif (Test-Path -LiteralPath (Join-Path $codexNodeModules 'sharp')) {
    $env:NODE_PATH = $codexNodeModules
} else {
    throw "The sharp package was not found. Run 'npm install' in $PSScriptRoot."
}

& $node (Join-Path $PSScriptRoot 'build-preview.js') $Source $Output
if ($LASTEXITCODE -ne 0) {
    throw "GIF generation failed with exit code $LASTEXITCODE."
}
