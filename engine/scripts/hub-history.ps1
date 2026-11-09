function Get-AriaPreviousSkin {
 param([string[]]$VisibleIds)
 $path=Join-Path $script:DreamHubHome 'previous-skin.dat'
 try{
  Assert-DreamSkinNoReparseComponents $path
  if(-not(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -gt 16384){return $null}
  $value=[AriaPrivacyCrypto]::Unprotect([IO.File]::ReadAllText($path))|ConvertFrom-Json
  if($value.schemaVersion -ne 1 -or $value.id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$' -or $value.displayMode -notin @('cover','contain','native')){return $null}
  if($null -ne $value.opacity -and ($value.opacity -isnot [ValueType] -or [double]$value.opacity -lt 0 -or [double]$value.opacity -gt 100)){return $null}
  if($PSBoundParameters.ContainsKey('VisibleIds')){if($value.id -notin $VisibleIds){return $null}}
  else{$null=Get-DreamHubThemeById $value.id}
  return $value
 }catch{return $null}
}
function Get-AriaCurrentSkinSnapshot {
 $active=Read-DreamHubJson (Join-Path $script:DreamHubState 'active-theme\theme.json') $null
 if($active.id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){return $null}
 return [pscustomobject]@{schemaVersion=1;id=[string]$active.id;opacity=(Get-DreamSkinLocalOpacity -ThemeId $active.id -StateRoot $script:DreamHubState);displayMode=(Get-DreamSkinDisplayMode -ThemeId $active.id -StateRoot $script:DreamHubState)}
}
function Save-AriaPreviousSkin {
 param($Previous,[string]$AppliedId)
 if(-not $Previous -or $Previous.id -ceq $AppliedId){return}
 $path=Join-Path $script:DreamHubHome 'previous-skin.dat'
 Assert-DreamSkinNoReparseComponents $path
 $protected=[AriaPrivacyCrypto]::Protect(($Previous|ConvertTo-Json -Compress))
 Write-DreamSkinUtf8FileAtomically -Path $path -Content $protected
}
