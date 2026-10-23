function Get-AriaStorageFiles {
 param([string]$Directory)
 if(-not(Test-Path -LiteralPath $Directory -PathType Container)){return @()}
 Assert-DreamSkinNoReparseComponents $Directory;$folders=[Collections.Generic.Queue[string]]::new();$folders.Enqueue($Directory)
 while($folders.Count){
  foreach($item in @(Get-ChildItem -LiteralPath $folders.Dequeue() -Force -ErrorAction SilentlyContinue)){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
   if($item.PSIsContainer){$folders.Enqueue($item.FullName)}else{$item}
  }
 }
}
function Get-AriaStorageCandidates {
 $age=[DateTime]::UtcNow.AddDays(-1);$candidates=@();$seen=@{}
 foreach($file in @(Get-AriaStorageFiles (Join-Path $script:DreamHubHome 'temp'))){if($file.LastWriteTimeUtc -lt $age){$candidates+=@($file)}}
 foreach($name in @('requests','backups\plans','backups\cleanup-plans')){
  $folder=Join-Path $script:DreamHubHome $name
  if(Test-Path -LiteralPath $folder){foreach($file in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue)){
   if($file.LastWriteTimeUtc -ge $age){continue}
   if($name -eq 'requests' -and $file.Name -cnotmatch '^[a-f0-9]{32}(?:\.[a-f0-9]{32}\.launch)?\.(?:request|result)\.json$'){continue}
   if($name -ne 'requests' -and $file.Name -cnotmatch '^[a-f0-9]{32}\.json$'){continue}
   $candidates+=@($file)
  }}
 }
 $saved=@(Get-DreamSkinSavedThemes -SkipImageMetadata|Select-Object -ExpandProperty Id)
 $folder=Join-Path $script:DreamHubHome 'thumbnails'
 if(Test-Path -LiteralPath $folder){foreach($file in @(Get-ChildItem -LiteralPath $folder -File)){if($file.BaseName -notin $saved -and $file.Name -cmatch '^[A-Za-z0-9_-]{1,100}\.(?:jpg|json)$' -and $file.LastWriteTimeUtc -lt $age){$candidates+=@($file)}}}
 $folder=Join-Path $script:DreamHubHome 'backups'
 if(Test-Path -LiteralPath $folder){$candidates+=@(Get-ChildItem -LiteralPath $folder -File -Force|Where-Object {$_.Name -cmatch '^\.restore-[a-f0-9]{32}\.decrypt\.zip$' -and $_.LastWriteTimeUtc -lt $age})}
 foreach($file in @($candidates|Sort-Object LastWriteTimeUtc|Select-Object -First 2000)){
  if($seen.ContainsKey($file.FullName)){continue};$seen[$file.FullName]=$true
  try{Assert-DreamSkinNoReparseComponents $file.FullName}catch{continue}
  [pscustomobject]@{path=$file.FullName;size=[long]$file.Length;ticks=$file.LastWriteTimeUtc.Ticks}
 }
}
function Get-AriaStorageOverview {
 $groups=@(
  @{key='skins';name='皮肤与当前背景';roots=@((Join-Path $script:DreamHubHome 'themes'),(Join-Path $script:DreamHubState 'themes'),(Join-Path $script:DreamHubState 'active-theme'))},
  @{key='saved';name='我的壁纸与下载原图';roots=@((Join-Path $script:DreamHubHome 'saved-wallpapers'),(Join-Path $script:DreamHubHome 'wuwa-downloads'))},
  @{key='previews';name='缩略图与网页预览';roots=@((Join-Path $script:DreamHubHome 'thumbnails'),(Join-Path $script:DreamHubHome 'workshop-thumbnails'))},
  @{key='browser';name='网页资料与登录缓存';roots=@((Join-Path $script:DreamHubHome 'browser-profile'),(Join-Path $script:DreamHubHome 'steam-profile'),(Join-Path $script:DreamHubHome 'wuwa-profile'))},
  @{key='tasks';name='录制与任务文件';roots=@($script:DreamSceneQueueRoot)},
  @{key='backup';name='备份与恢复快照';roots=@((Get-AriaBackupRoot))},
  @{key='temp';name='临时文件';roots=@((Join-Path $script:DreamHubHome 'temp'),(Join-Path $script:DreamHubHome 'requests'))}
 )
 $items=@()
 foreach($group in $groups){[long]$bytes=0;foreach($folder in $group.roots){if($folder){foreach($file in @(Get-AriaStorageFiles $folder)){$bytes+=$file.Length}}};$items+=@([pscustomobject]@{key=$group.key;name=$group.name;sizeMB=[Math]::Round($bytes/1MB,1)})}
 $candidates=@(Get-AriaStorageCandidates);$id=[guid]::NewGuid().ToString('N');$folder=Join-Path (Get-AriaBackupRoot) 'cleanup-plans';Assert-DreamSkinNoReparseComponents $folder;[void][IO.Directory]::CreateDirectory($folder)
 Write-DreamHubJson (Join-Path $folder ($id+'.json')) @{expires=[DateTime]::UtcNow.AddMinutes(15).ToString('o');files=@($candidates)}
 [long]$release=0;foreach($item in $candidates){$release+=$item.size}
 return [pscustomobject]@{groups=@($items);cleanupPlanId=$id;cleanupCount=$candidates.Count;cleanupMB=[Math]::Round($release/1MB,2);freeGB=[Math]::Round(([IO.DriveInfo]::new('D:\')).AvailableFreeSpace/1GB,1)}
}
function Clear-AriaStoragePlan {
 param([ValidatePattern('^[a-f0-9]{32}$')][string]$PlanId)
 $root=Join-Path (Get-AriaBackupRoot) 'cleanup-plans';$path=Join-Path $root ($PlanId+'.json');Assert-DreamSkinNoReparseComponents $path;$plan=Read-DreamHubJson $path $null
 if(-not $plan -or [DateTime]::Parse($plan.expires).ToUniversalTime() -lt [DateTime]::UtcNow){throw '清理预览已过期，请重新检查空间。'}
 $current=@{};foreach($item in @(Get-AriaStorageCandidates)){$current[$item.path]=$item}
 $count=0;[long]$released=0;$skipped=0
 foreach($item in @($plan.files)){
  $candidate=$current[[string]$item.path]
  if(-not $candidate -or $candidate.size -ne $item.size -or $candidate.ticks -ne $item.ticks){$skipped++;continue}
  try{
   Assert-DreamSkinNoReparseComponents $candidate.path
   $lock=[IO.File]::Open($candidate.path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$lock.Dispose()
   Assert-DreamSkinNoReparseComponents $candidate.path;[IO.File]::Delete($candidate.path);$count++;$released+=$candidate.size
  }catch{$skipped++}
 }
 [IO.File]::Delete($path)
 return [pscustomobject]@{cleared=$count;skipped=$skipped;message=('已清理 '+$count+' 个临时文件，释放约 '+[Math]::Round($released/1MB,2)+' MB'+$(if($skipped){'；正在使用或已变化的文件已跳过'}else{''}))}
}
