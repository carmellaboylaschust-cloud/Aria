param([string]$EngineRoot=(Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference='Stop'
$testRoot=Join-Path $PSScriptRoot ('.history-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
try{
 . (Join-Path $EngineRoot 'scripts\hub-privacy.ps1')
 . (Join-Path $EngineRoot 'scripts\hub-history.ps1')
 $script:DreamHubHome=$testRoot;$script:DreamHubState=$testRoot
 function Assert-DreamSkinNoReparseComponents($Path){if(-not([IO.Path]::GetFullPath($Path).StartsWith($testRoot+'\'))){throw 'outside fixture'}}
 function Write-DreamSkinUtf8FileAtomically($Path,$Content){[IO.File]::WriteAllText($Path,$Content)}
 function Get-DreamHubThemeById($Id){if($Id -ne 'allowed'){throw 'access denied'};return @{id=$Id}}
 function Read-DreamHubJson($Path,$Default){return @{id='allowed'}}
 function Get-DreamSkinLocalOpacity {param($ThemeId,$StateRoot);return 31}
 function Get-DreamSkinDisplayMode {param($ThemeId,$StateRoot);return 'contain'}
 $current=Get-AriaCurrentSkinSnapshot
 if($current.id -ne 'allowed' -or $current.opacity -ne 31 -or $current.displayMode -ne 'contain'){throw 'snapshot settings'}
 Save-AriaPreviousSkin -Previous $current -AppliedId 'next'
 $path=Join-Path $testRoot 'previous-skin.dat';$encrypted=[IO.File]::ReadAllText($path)
 if($encrypted.Contains('allowed')){throw 'history plaintext'}
 if((Get-AriaPreviousSkin).id -ne 'allowed'){throw 'authorized restore'}
 if(Get-AriaPreviousSkin -VisibleIds @('other')){throw 'hidden history leak'}
 if(-not(Get-AriaPreviousSkin -VisibleIds @('allowed'))){throw 'visible history missing'}
 Save-AriaPreviousSkin -Previous @{id='next'} -AppliedId 'next'
 if([IO.File]::ReadAllText($path) -cne $encrypted){throw 'same skin overwrote history'}
 Save-AriaPreviousSkin -Previous @{schemaVersion=1;id='private-fixture';opacity=40;displayMode='cover'} -AppliedId 'next'
 if(Get-AriaPreviousSkin){throw 'locked theme restored'}
 if(Get-AriaPreviousSkin -VisibleIds @('allowed')){throw 'private title exposed'}
 [IO.File]::WriteAllText($path,'corrupted');if(Get-AriaPreviousSkin){throw 'corrupt history accepted'}
 Write-Output 'PASS: encrypted history, original settings, visibility/access checks, same-theme preservation, corrupted-data recovery'
}finally{
 $full=[IO.Path]::GetFullPath($testRoot);$parent=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
 if($full.StartsWith($parent) -and [IO.Path]::GetFileName($full) -match '^\.history-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
}
