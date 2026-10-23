function Get-AriaLibraryMeta {
 param([switch]$ForWrite)
 $path=Join-Path $script:DreamHubHome 'library-meta.json'
 $value=Read-DreamHubJson $path $null
 if(-not $value -or $value.schemaVersion -ne 1 -or -not $value.themes){
  if($ForWrite -and (Test-Path -LiteralPath $path)){throw '收藏资料文件无法读取，原文件已保留，请先从备份恢复。'}
  return [pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}}
 }
 return $value
}
function Set-AriaLibraryMeta {
 param([string[]]$Ids,[string]$Name,[string]$Group,[string[]]$Tags,[switch]$RecordUse)
 $ids=@($Ids|Select-Object -Unique)
 if(-not $ids.Count -or $ids.Count -gt 100){throw '请选择 1 至 100 张皮肤。'}
 foreach($id in $ids){$null=Get-DreamHubThemeById $id}
 if($Name.Length -gt 70 -or $Group.Length -gt 30 -or $Tags.Count -gt 12){throw '名称最多 70 字，分组最多 30 字，标签最多 12 个。'}
 $cleanTags=@($Tags|ForEach-Object {([string]$_).Trim()}|Where-Object {$_}|Select-Object -Unique)
 if(@($cleanTags|Where-Object {$_.Length -gt 20}).Count){throw '单个标签最多 20 字。'}
 $guard=Enter-DreamSceneMutex 'LibraryMeta';if(-not $guard){throw '收藏资料正在保存，请稍后重试。'}
 try{
  $meta=Get-AriaLibraryMeta -ForWrite
  foreach($id in $ids){
   $entry=$meta.themes.PSObject.Properties[$id]
   if(-not $entry){$meta.themes|Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{});$entry=$meta.themes.PSObject.Properties[$id]}
   if($RecordUse){$entry.Value|Add-Member -NotePropertyName lastUsed -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force}
   else{
    if($ids.Count -eq 1 -and $PSBoundParameters.ContainsKey('Name')){if(-not $Name.Trim()){throw '皮肤名称不能为空。'};$entry.Value|Add-Member -NotePropertyName name -NotePropertyValue $Name.Trim() -Force}
    $entry.Value|Add-Member -NotePropertyName group -NotePropertyValue $Group.Trim() -Force
    $entry.Value|Add-Member -NotePropertyName tags -NotePropertyValue @($cleanTags) -Force
   }
  }
  Write-DreamHubJson (Join-Path $script:DreamHubHome 'library-meta.json') $meta
 }finally{Exit-DreamSceneMutex $guard}
}
function Get-AriaWorkshopIdFromTheme {
 param($Theme)
 if([string]$Theme.sourceWorkshopId -cmatch '^\d{6,12}$'){return [string]$Theme.sourceWorkshopId}
 if([string]$Theme.sourceSceneProject -match '\\431960\\(\d{6,12})\\project.json$'){return $Matches[1]}
 return ''
}
function Get-AriaDownloadedWallpapers {
 $themes=@(Get-DreamSkinSavedThemes -SkipImageMetadata);$hiddenIds=@(Get-AriaHiddenIds);$unlocked=Test-AriaGrant -Role hidden
 $imported=@{};$private=@{}
 foreach($entry in $themes){
  try{
   $meta=Read-DreamHubJson (Join-Path $entry.Path 'theme.json') $null;$id=Get-AriaWorkshopIdFromTheme $meta
   if(-not $id){continue}
   if($entry.Id -in $hiddenIds -and -not $unlocked){$private[$id]=$true}else{$imported[$id]=$entry.Id}
  }catch{}
 }
 $jobs=@(Get-DreamSceneJobs|Where-Object {-not $_.testOnly});$items=@()
 $thumbRoot=Join-Path $script:DreamHubHome 'workshop-thumbnails';Assert-DreamSkinNoReparseComponents $thumbRoot;[void][IO.Directory]::CreateDirectory($thumbRoot)
 foreach($root in @(Get-DreamHubWorkshopRoots)){
  foreach($folder in @(Get-ChildItem -LiteralPath $root -Directory)){
   $id=$folder.Name;if($id -cnotmatch '^\d{6,12}$' -or $private.ContainsKey($id)){continue}
   $path=Join-Path $folder.FullName 'project.json'
   if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
   try{
    Assert-DreamSkinNoReparseComponents $path;if((Get-Item -LiteralPath $path).Length -gt 2MB){continue}
    $project=Read-DreamHubJson $path $null;if(-not $project){continue}
    $name=([string]$project.title).Trim();if(-not $name){$name='Steam '+$id};if($name.Length -gt 120){$name=$name.Substring(0,120)}
    $type=([string]$project.type).ToLowerInvariant();$ready=Test-DreamHubWorkshopReady $root $id;$reason=''
    if($type -notin @('video','scene','web')){$reason='仅支持视频、Scene 和 Web 壁纸。'}
    if(-not $ready){$reason='Steam 尚未下载完整，完成后可导入。'}
    $preview=''
    $relative=if($project.preview){[string]$project.preview}else{'preview.jpg'}
    if(-not [IO.Path]::IsPathRooted($relative)){
     $picture=[IO.Path]::GetFullPath((Join-Path $folder.FullName $relative));$ext=[IO.Path]::GetExtension($picture).ToLowerInvariant()
     if((Test-DreamSkinThemePathWithin $picture $folder.FullName) -and $ext -in @('.jpg','.jpeg','.png','.webp','.gif') -and (Test-Path -LiteralPath $picture -PathType Leaf)){
      Assert-DreamSkinNoReparseComponents $picture;$pi=Get-Item -LiteralPath $picture
      if($pi.Length -le 8MB){
       $copy=Join-Path $thumbRoot ($id+$ext)
       $stamp=Join-Path $thumbRoot ($id+'.stamp')
       $key=$pi.Length.ToString()+':'+$pi.LastWriteTimeUtc.Ticks.ToString()
       if(-not(Test-Path -LiteralPath $copy) -or -not(Test-Path -LiteralPath $stamp) -or [IO.File]::ReadAllText($stamp) -cne $key){
        Assert-DreamSkinNoReparseComponents $copy;[IO.File]::Copy($picture,$copy,$true);[IO.File]::WriteAllText($stamp,$key)
       }
       $preview=ConvertTo-DreamHubMediaUrl $copy
      }
     }
    }
    $latest=@($jobs|Where-Object {$_.workshopId -eq $id}|Sort-Object updatedAt -Descending|Select-Object -First 1)
    $jobStatus=if($latest.Count){$latest[0].status}else{''}
    $items+=@([pscustomobject]@{id=$id;name=$name;type=$type;preview=$preview;ready=[bool]$ready;reason=$reason;themeId=[string]$imported[$id];jobStatus=$jobStatus})
   }catch{}
  }
 }
 return @($items|Sort-Object name,id)
}
