function Get-DreamHubHeroes {
 $feedHome=$script:DreamHubHome
 $manifest=Read-DreamHubJson (Join-Path $feedHome 'daily-wallpapers\current.json') $null
 if($manifest.schemaVersion -eq 1 -and @($manifest.heroes).Count -eq 4){
  $items=@()
  foreach($hero in $manifest.heroes){
   if($hero.hash -cnotmatch '^[a-f0-9]{64}$' -or $hero.relativePath -cnotmatch '^daily-wallpapers/cache/[a-f0-9]{64}\.(jpg|jpeg|png|webp|gif)$'){$items=@();break}
   $source=Join-Path $feedHome $hero.relativePath
   if(-not(Test-Path -LiteralPath $source -PathType Leaf)){$items=@();break}
   Assert-DreamSkinNoReparseComponents $source
   $items+=@([pscustomobject]@{id=$hero.id;title=$hero.title;url=(ConvertTo-DreamHubMediaUrl $source);localPath=$source;hash=$hero.hash;original=$hero.original;source='https://wuwa.games/';slot=$manifest.slot})
  }
  if($items.Count -eq 4){return $items}
 }
 $codeRoot=Split-Path $PSScriptRoot
 $fallback=@(Read-DreamHubJson (Join-Path $codeRoot 'hub\heroes.json') @())
 $items=@()
 for($i=0;$i -lt $fallback.Count;$i++){
  $hero=$fallback[$i]
  $source=Join-Path (Join-Path $codeRoot 'hub\media') $hero.file
  $items+=@([pscustomobject]@{id=('builtin-hero-'+$i);title=$hero.title;file=$hero.file;localPath=$source;hash='';original=$hero.original;source=$hero.source;slot=''})
 }
 return $items
}
function Save-DreamHubHero {
 param([int]$Index,[string]$HeroId)
 $heroes=@(Get-DreamHubHeroes)
 if($HeroId){$hero=@($heroes|Where-Object {$_.id -ceq $HeroId})|Select-Object -First 1;if(-not $hero){throw '首页推荐已更新，请重新选择一张。'}}
 else{if($Index -lt 0 -or $Index -ge $heroes.Count){throw '壁纸不存在。'};$hero=$heroes[$Index]}
 $source=$hero.localPath;Assert-DreamHubMediaPolicy $source
 $saved=Join-Path $script:DreamHubHome 'saved-wallpapers';Assert-DreamSkinNoReparseComponents $saved;[void][IO.Directory]::CreateDirectory($saved)
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $title=[regex]::Replace([string]$hero.title,'[\\/:*?"<>|\x00-\x1f]','_').Trim().TrimEnd('.')
 if(-not $title){$title='鸣潮壁纸'};if($title.Length -gt 60){$title=$title.Substring(0,60)}
 $destination=Join-Path $saved ($title+'-'+$hash.Substring(0,12)+[IO.Path]::GetExtension($source))
 Assert-DreamSkinNoReparseComponents $destination
 if(-not(Test-Path -LiteralPath $destination)){Copy-Item -LiteralPath $source -Destination $destination}
 $import=Import-DreamSkinLocalMedia $destination
 $import.Theme.name='鸣潮 · '+$hero.title;Write-DreamSkinTheme $import.Directory $import.Theme
 return $import
}
function Start-DreamHubDailyWorker {
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $info.Arguments=ConvertTo-DreamSkinArgumentLine @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $PSScriptRoot 'daily-wallpapers-worker.ps1'))
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
 $p=[Diagnostics.Process]::Start($info);if($p){$p.Dispose()}
}
