[CmdletBinding()]
param(
    [string]$Preview,
    [UInt64]$PublishedFileId = 3795345529,
    [UInt32]$AppId = 108600,
    [switch]$CheckOnly,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Preview)) {
    $Preview = Join-Path $PSScriptRoot '..\..\workshop-preview.gif'
}
& (Join-Path $PSScriptRoot '..\..\..\tools\workshop-preview\upload-preview.ps1') -Preview $Preview -PublishedFileId $PublishedFileId -AppId $AppId -CheckOnly:$CheckOnly -WhatIf:$WhatIf
