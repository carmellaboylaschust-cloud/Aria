. (Join-Path $PSScriptRoot 'hub-policy.ps1')
function Import-DreamSkinLocalMedia {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [ValidateSet('light','dark','auto')][string]$Appearance='dark',
    [string]$StateRoot='D:\Aria\runtime'
  )
  $source=[IO.Path]::GetFullPath($Path)
  Assert-DreamHubMediaPolicy -Path $source
  Assert-DreamSkinImageFile -Path $source
  $paths=Get-DreamSkinThemePaths -StateRoot $StateRoot
  $library=Get-DreamSkinLocalLibraryRoot -StateRoot $StateRoot
  Ensure-DreamSkinManagedDirectory -Path $library -Root $library
  $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  foreach($directory in Get-ChildItem -LiteralPath $library -Directory) {
    $metadataPath=Join-Path $directory.FullName 'theme.json'
    if(-not(Test-Path -LiteralPath $metadataPath)){continue}
    try {
      $metadata=Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if($metadata.localSourceHash -ceq $hash){$existing=Read-DreamSkinTheme -ThemeDirectory $directory.FullName;$existing|Add-Member -NotePropertyName AlreadyExists -NotePropertyValue $true -Force;return $existing}
    } catch {}
  }
  $id='local-'+(Get-Date).ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
  $destination=Join-Path $library $id
  Ensure-DreamSkinManagedDirectory -Path $destination -Root $library
  try {
    $file='art'+[IO.Path]::GetExtension($source).ToLowerInvariant()
    Copy-Item -LiteralPath $source -Destination (Join-Path $destination $file)
    $name=[IO.Path]::GetFileNameWithoutExtension($source)
    if($name.Length -gt 70){$name=$name.Substring(0,70)}
    $theme=[pscustomobject]@{
      schemaVersion=1; id=$id; name=$name; image=$file; appearance=$Appearance; localSourceHash=$hash
      art=[pscustomobject]@{focusX=0.5;focusY=0.5;safeArea='none';taskMode='full'}
    }
    Write-DreamSkinTheme -ThemeDirectory $destination -Theme $theme
    $created=Read-DreamSkinTheme -ThemeDirectory $destination
    $created|Add-Member -NotePropertyName AlreadyExists -NotePropertyValue $false -Force
    return $created
  } catch {
    if(Test-DreamSkinThemePathWithin -Path $destination -Root $library){
      Remove-DreamSkinManagedDirectoryVerified -Path $destination -Root $library
    }
    throw
  }
}

function Get-DreamSkinLocalOpacity {
  param([string]$ThemeId,[string]$StateRoot='D:\Aria\runtime')
  try {
    $prefs=Get-Content -LiteralPath (Join-Path $StateRoot 'theme-preferences.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry=$prefs.themes.PSObject.Properties[$ThemeId]
    if($entry -and $null -ne $entry.Value.transparency){return [int](100-$entry.Value.transparency)}
  }catch{}
  return $null
}

function Set-DreamSkinLocalOpacity {
  param([string]$ThemeId,[AllowNull()][object]$Opacity,[string]$StateRoot='D:\Aria\runtime')
  $path=Join-Path $StateRoot 'theme-preferences.json'
  if($null -ne $Opacity -and ([int]$Opacity -lt 0 -or [int]$Opacity -gt 100)){throw '不透明度范围为 0–100'}
  $prefs=if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json}else{[pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}}}
  if($prefs.schemaVersion -ne 1 -or $null -eq $prefs.themes){throw '原透明度设置无法读取，已保留文件。'}
  $entry=$prefs.themes.PSObject.Properties[$ThemeId]
  if(-not $entry){$prefs.themes|Add-Member -NotePropertyName $ThemeId -NotePropertyValue ([pscustomobject]@{});$entry=$prefs.themes.PSObject.Properties[$ThemeId]}
  if($null -eq $Opacity){$entry.Value.PSObject.Properties.Remove('transparency')}
  else{$entry.Value|Add-Member -NotePropertyName transparency -NotePropertyValue (100-[int]$Opacity) -Force}
  Write-DreamSkinUtf8FileAtomically -Path $path -Content (($prefs|ConvertTo-Json -Depth 8)+"`r`n")
}

function Get-DreamSkinDisplayMode {
  param([string]$ThemeId,[string]$StateRoot='D:\Aria\runtime')
  try{$prefs=Get-Content -LiteralPath (Join-Path $StateRoot 'theme-preferences.json') -Raw -Encoding UTF8|ConvertFrom-Json;$mode=$prefs.themes.PSObject.Properties[$ThemeId].Value.displayMode;if($mode -in @('cover','contain','native')){return $mode}}catch{}
  return 'cover'
}
function Set-DreamSkinDisplayMode {
  param([string]$ThemeId,[ValidateSet('cover','contain','native')][string]$Mode,[string]$StateRoot='D:\Aria\runtime')
  if($ThemeId -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){throw '皮肤编号无效。'}
  $path=Join-Path $StateRoot 'theme-preferences.json';Assert-DreamSkinNoReparseComponents $path
  $prefs=if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json}else{[pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}}}
  if($prefs.schemaVersion -ne 1 -or $null -eq $prefs.themes){throw '皮肤设置无法读取，已保留原文件。'}
  $entry=$prefs.themes.PSObject.Properties[$ThemeId]
  if(-not $entry){$prefs.themes|Add-Member -NotePropertyName $ThemeId -NotePropertyValue ([pscustomobject]@{});$entry=$prefs.themes.PSObject.Properties[$ThemeId]}
  $entry.Value|Add-Member -NotePropertyName displayMode -NotePropertyValue $Mode -Force
  Write-DreamSkinUtf8FileAtomically -Path $path -Content (($prefs|ConvertTo-Json -Depth 8)+[Environment]::NewLine)
}
