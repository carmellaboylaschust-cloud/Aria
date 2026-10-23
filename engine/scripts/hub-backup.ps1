function Read-AriaBackupJson {
 param([string]$Path,$Default)
 if(-not(Test-Path -LiteralPath $Path)){return ,$Default}
 Assert-DreamSkinNoReparseComponents $Path
 if((Get-Item -LiteralPath $Path).Length -gt 1MB){throw '备份设置文件过大。'}
 $raw=Read-DreamSkinUtf8File -Path $Path
 if($raw -match '^\s*\[\s*\]\s*$'){return ,@()}
 try{$value=$raw|ConvertFrom-Json -ErrorAction Stop}catch{throw '设置文件无法读取，原文件已保留。'}
 if($null -eq $value){throw '设置文件内容为空或无效。'}
 if($raw.TrimStart().StartsWith('[')){$plain=[object[]]@($value|ForEach-Object {$_});return ,$plain}
 return ,$value
}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
function Initialize-AriaBackupCrypto {
 if(-not('AriaBackupSink' -as [type])){Add-Type -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\AriaBackupCrypto.cs')}
}
function Get-AriaBackupRoot {
 $root=Join-Path $script:DreamHubHome 'backups';Assert-DreamSkinNoReparseComponents $root;[void][IO.Directory]::CreateDirectory($root);return $root
}
function Assert-AriaPrivateBackupAccess {
 param([string]$AdminToken)
 if(-not(Test-AriaGrant -Role hidden) -or -not(Test-AriaGrant -Token $AdminToken -Role admin)){throw '请保持隐藏列表已解锁，并完成管理员验证后再备份或恢复隐藏收藏。'}
}
function Assert-AriaArchiveName {
 param([string]$Name)
 if(-not $Name -or $Name.Length -gt 240 -or $Name.Contains('\') -or $Name.Contains(':') -or $Name.StartsWith('/') -or $Name.EndsWith('/')){throw '备份包含不安全的路径。'}
 foreach($part in ($Name -split '/')){
  if(-not $part -or $part -in @('.','..') -or $part.TrimEnd(' ','.') -cne $part -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw '备份包含不安全的路径。'}
 }
 if($Name -cne 'manifest.json' -and $Name -cnotmatch '^(skins/[A-Za-z0-9_-]{1,100}/.+|settings/[A-Za-z0-9._-]+\.json)$'){throw '备份路径不属于皮肤或设置。'}
}
function Copy-AriaArchiveStream {
 param([IO.Stream]$InputStream,[IO.Stream]$OutputStream,[long]$Limit=268435456)
 $hash=[Security.Cryptography.SHA256]::Create();$buffer=New-Object byte[] 65536;[long]$total=0
 try{
  while(($count=$InputStream.Read($buffer,0,$buffer.Length)) -gt 0){$total+=$count;if($total -gt $Limit){throw '备份单个文件超出允许的大小。'};$OutputStream.Write($buffer,0,$count);[void]$hash.TransformBlock($buffer,0,$count,$buffer,0)}
  [void]$hash.TransformFinalBlock((New-Object byte[] 0),0,0)
  return [pscustomobject]@{size=$total;sha256=([BitConverter]::ToString($hash.Hash).Replace('-','').ToLowerInvariant())}
 }finally{$hash.Dispose()}
}
function Add-AriaArchiveEntry {
 param($Archive,[string]$Name,[string]$SourcePath,[AllowNull()][string]$Text)
 Assert-AriaArchiveName $Name
 $entry=$Archive.CreateEntry($Name,[IO.Compression.CompressionLevel]::NoCompression)
 $output=$entry.Open();$input=$null
 try{
  if($SourcePath){Assert-DreamSkinNoReparseComponents $SourcePath;$input=[IO.File]::OpenRead($SourcePath)}
  else{$input=[IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Text))}
  $result=Copy-AriaArchiveStream $input $output
  return [pscustomobject]@{path=$Name;size=$result.size;sha256=$result.sha256}
 }finally{if($input){$input.Dispose()};$output.Dispose()}
}
function Select-AriaBackupMap {
 param($Map,[string[]]$Ids)
 $filtered=[ordered]@{};foreach($property in $Map.PSObject.Properties){if($property.Name -in $Ids){$filtered[$property.Name]=$property.Value}}
 return [pscustomobject]$filtered
}
function Get-AriaBackupCatalog {
 param([ValidateSet('public','private')][string]$Scope)
 $hidden=@(Get-AriaHiddenIds);$files=@();$ids=@();[long]$total=0
 foreach($entry in @(Get-DreamSkinSavedThemes -SkipImageMetadata)){
  if(($entry.Id -in $hidden) -ne ($Scope -eq 'private')){continue}
  $loaded=Read-DreamSkinTheme $entry.Path -SkipImageMetadata
  if($loaded.Theme.archived){continue}
  if($entry.Id -in $ids){throw '皮肤编号重复，已停止备份。'};$ids+=@($entry.Id);$folders=[Collections.Generic.Queue[string]]::new();$folders.Enqueue($entry.Path)
  while($folders.Count){
   $folder=$folders.Dequeue();Assert-DreamSkinNoReparseComponents $folder
   foreach($item in @(Get-ChildItem -LiteralPath $folder -Force)){
    Assert-DreamSkinNoReparseComponents $item.FullName
    if($item.PSIsContainer){$folders.Enqueue($item.FullName);continue}
    if($item.Extension.ToLowerInvariant() -notin @('.json','.css','.jpg','.jpeg','.png','.gif','.webp','.mp4','.webm')){continue}
    if($item.Length -gt 256MB){throw '单个皮肤文件超过 256 MB，请先单独保留原文件。'}
    $relative=$item.FullName.Substring($entry.Path.TrimEnd('\').Length+1).Replace('\','/')
    $name='skins/'+$entry.Id+'/'+$relative;Assert-AriaArchiveName $name
    $files+=@([pscustomobject]@{path=$name;source=$item.FullName;text=$null;size=$item.Length});$total+=$item.Length
   }
  }
 }
 $metadata=Get-AriaLibraryMeta -ForWrite
 $settings=[ordered]@{'library-meta.json'=[pscustomobject]@{schemaVersion=1;themes=(Select-AriaBackupMap $metadata.themes $ids)}}
 if($Scope -eq 'public'){
  foreach($name in @('prompts.json','window-settings.json','import-policy.json','playback-settings.json','privacy-preferences.json')){
   $path=Join-Path $script:DreamHubHome $name
   if(Test-Path -LiteralPath $path){Assert-DreamSkinNoReparseComponents $path;if((Get-Item $path).Length -gt 1MB){throw '设置文件过大，已停止备份。'};$value=Read-AriaBackupJson $path $null;if($name -eq 'prompts.json'){foreach($prompt in @($value)){if($prompt.sceneThemeId -and $prompt.sceneThemeId -notin $ids){$prompt.sceneThemeId=''}}};if($name -eq 'privacy-preferences.json' -and $value.safeThemeId -notin $ids){$value.safeThemeId=''};$settings[$name]=$value}
  }
  $settings['favorites.json']=@(Read-DreamHubJson (Join-Path $script:DreamHubHome 'favorites.json') @()|Where-Object {$_ -in $ids})
 }else{$settings['privacy.json']=Get-AriaPrivacyConfig}
 $preferences=Read-DreamHubJson (Join-Path $script:DreamHubState 'theme-preferences.json') $null
 if($preferences){$settings['theme-preferences.json']=[pscustomobject]@{schemaVersion=1;themes=(Select-AriaBackupMap $preferences.themes $ids)}}
 foreach($name in $settings.Keys){$text=ConvertTo-Json -InputObject $settings[$name] -Depth 14 -Compress;$length=[Text.Encoding]::UTF8.GetByteCount($text);$files+=@([pscustomobject]@{path=('settings/'+$name);source='';text=$text;size=$length});$total+=$length}
 if($files.Count -gt 3000 -or $total -gt 1800MB){throw '此备份超过 1800 MB 或 3000 个文件，请分批整理后重试。'}
 if(([IO.DriveInfo]::new('D:\')).AvailableFreeSpace -lt ($total+512MB)){throw 'D 盘空间不足，无法创建完整备份。'}
 return [pscustomobject]@{files=@($files);ids=@($ids);scope=$Scope;totalBytes=$total}
}
function Export-AriaBackup {
 param([string]$Path,[ValidateSet('public','private')][string]$Scope='public',[string]$Password,[string]$AdminToken)
 $Path=[IO.Path]::GetFullPath($Path)
 if([IO.Path]::GetPathRoot($Path) -ine 'D:\' -or [IO.Path]::GetExtension($Path) -notin @('.zip','.ariavault')){throw '备份只保存在 D 盘，请选择 ZIP 或 Aria 加密备份文件。'}
 if([IO.Path]::GetExtension($Path) -ine $(if($Scope -eq 'private'){'.ariavault'}else{'.zip'})){throw '普通备份使用 ZIP，隐藏备份使用 .ariavault 格式。'}
 Assert-DreamSkinNoReparseComponents $Path
 if($Scope -eq 'private'){Assert-AriaPrivateBackupAccess $AdminToken;if($Password.Trim().Length -lt 8 -or $Password.Length -gt 128){throw '备份密码需为 8 至 128 字。'}}
 $catalog=Get-AriaBackupCatalog $Scope;$temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.part'
 $sink=$null;$stream=$null;$archive=$null
 try{
  if($Scope -eq 'private'){Initialize-AriaBackupCrypto;$sink=[AriaBackupSink]::new($temporary,$Password);$stream=$sink.Stream}
  else{$stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
  $archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  $records=@();foreach($file in $catalog.files){$records+=@(Add-AriaArchiveEntry -Archive $archive -Name $file.path -SourcePath $file.source -Text $file.text)}
  $manifest=[pscustomobject]@{format='aria-backup/1';createdAt=[DateTime]::UtcNow.ToString('o');scope=$Scope;skinIds=@($catalog.ids);files=@($records);totalBytes=$catalog.totalBytes}
  $manifestText=$manifest|ConvertTo-Json -Depth 12 -Compress;if([Text.Encoding]::UTF8.GetByteCount($manifestText) -gt 1MB){throw '备份清单过大，请分批整理后重试。'};$null=Add-AriaArchiveEntry -Archive $archive -Name 'manifest.json' -Text $manifestText
  $archive.Dispose();$archive=$null
  if($Scope -eq 'private'){Assert-AriaPrivateBackupAccess $AdminToken;$sink.Complete();$sink.Dispose();$sink=$null;$stream=$null}
  else{$nowHidden=@(Get-AriaHiddenIds);if(@($catalog.ids|Where-Object {$_ -in $nowHidden}).Count){throw '导出期间有皮肤移入隐藏列表，已停止普通备份，请重新导出。'};$stream.Dispose();$stream=$null}
  if(Test-Path -LiteralPath $Path){$previous=$Path+'.previous-'+[guid]::NewGuid().ToString('N');[IO.File]::Replace($temporary,$Path,$previous);[IO.File]::Delete($previous)}else{[IO.File]::Move($temporary,$Path)}
  return [pscustomobject]@{path=$Path;skinCount=$catalog.ids.Count;message=('已导出 '+$catalog.ids.Count+' 张'+$(if($Scope -eq 'private'){'隐藏皮肤，加密备份已保存在 D 盘'}else{'普通皮肤，备份已保存在 D 盘'}))}
 }finally{if($archive){try{$archive.Dispose()}catch{}};if($sink){try{$sink.Dispose()}catch{}}elseif($stream){$stream.Dispose()};if(Test-Path -LiteralPath $temporary){Assert-DreamSkinNoReparseComponents $temporary;[IO.File]::Delete($temporary)}}
}
function Read-AriaArchiveManifest {
 param($Archive)
 if($Archive.Entries.Count -gt 3001){throw '备份文件数量超出限制。'}
 $seen=@{}
 foreach($entry in $Archive.Entries){Assert-AriaArchiveName $entry.FullName;if($seen.ContainsKey($entry.FullName)){throw '备份包含重复路径。'};$seen[$entry.FullName]=$true;if($entry.Length -lt 0 -or $entry.Length -gt 256MB){throw '备份单个文件超出限制。'}}
 $entry=$Archive.GetEntry('manifest.json');if(-not $entry -or $entry.Length -gt 1MB){throw '未找到有效的 Aria 备份清单。'}
 $stream=$entry.Open();$memory=[IO.MemoryStream]::new()
 try{$null=Copy-AriaArchiveStream $stream $memory 1MB;$manifest=[Text.UTF8Encoding]::new($false,$true).GetString($memory.ToArray())|ConvertFrom-Json}finally{$stream.Dispose();$memory.Dispose()}
 if($manifest.format -cne 'aria-backup/1' -or $manifest.scope -notin @('public','private') -or @($manifest.files).Count -ne $Archive.Entries.Count-1){throw '备份清单格式不受支持。'}
 $ids=@($manifest.skinIds);if(@($ids|Select-Object -Unique).Count -ne $ids.Count -or @($ids|Where-Object {$_ -cnotmatch '^[A-Za-z0-9_-]{1,100}$'}).Count){throw '备份包含无效的皮肤编号。'}
 $listed=@{};[long]$sum=0
 foreach($file in @($manifest.files)){
  Assert-AriaArchiveName ([string]$file.path)
  if($file.path -ceq 'manifest.json' -or $listed.ContainsKey($file.path) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $file.size -lt 0 -or $file.size -gt 256MB){throw '备份文件清单无效。'}
  if($file.path.StartsWith('skins/',[StringComparison]::Ordinal) -and [IO.Path]::GetExtension([string]$file.path).ToLowerInvariant() -notin @('.json','.css','.jpg','.jpeg','.png','.gif','.webp','.mp4','.webm')){throw '备份包含不允许的皮肤文件格式。'}
  $listed[$file.path]=$true;$match=$Archive.GetEntry($file.path);if(-not $match -or $match.Length -ne $file.size){throw '备份文件大小与清单不符。'};$sum+=[long]$file.size
  if($file.path -cmatch '^skins/([^/]+)/' -and $Matches[1] -notin $ids){throw '备份包含未登记皮肤。'}
 }
 foreach($id in $ids){if(-not $listed.ContainsKey('skins/'+$id+'/theme.json')){throw '备份皮肤缺少主题说明。'}}
 if($sum -gt 1800MB -or $sum -ne $manifest.totalBytes){throw '备份总大小无效或超出限制。'}
 return $manifest
}
function Open-AriaBackupRead {
 param([string]$Path,[string]$Password,[string]$AdminToken)
 Assert-DreamSkinNoReparseComponents $Path
 $item=Get-Item -LiteralPath $Path -ErrorAction Stop;if($item.Length -gt 2GB -or $item.Length -lt 1){throw '备份文件大小无效。'}
 $temporary=$null;$stream=$null;$archive=$null
 try{
  $encrypted=$item.Extension -ieq '.ariavault'
  if($encrypted){
   Assert-AriaPrivateBackupAccess $AdminToken;Initialize-AriaBackupCrypto
   $temporary=Join-Path (Get-AriaBackupRoot) ('.restore-'+[guid]::NewGuid().ToString('N')+'.decrypt.zip')
   try{[AriaBackupCrypto]::Decrypt($item.FullName,$temporary,$Password)}catch{throw '备份密码不正确，或加密备份已损坏。'}
   $readPath=$temporary
  }else{$readPath=$item.FullName}
  $stream=[IO.File]::OpenRead($readPath);$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
  $manifest=Read-AriaArchiveManifest $archive
  if(($manifest.scope -eq 'private') -ne $encrypted){throw '隐藏收藏必须使用加密备份格式。'}
  return [pscustomobject]@{archive=$archive;stream=$stream;manifest=$manifest;temporary=$temporary}
 }catch{if($archive){$archive.Dispose()};if($stream){$stream.Dispose()};if($temporary -and (Test-Path -LiteralPath $temporary)){[IO.File]::Delete($temporary)};throw}
}
function Close-AriaBackupRead {
 param($Opened)
 if($Opened){$Opened.archive.Dispose();$Opened.stream.Dispose();if($Opened.temporary -and (Test-Path -LiteralPath $Opened.temporary)){Assert-DreamSkinNoReparseComponents $Opened.temporary;[IO.File]::Delete($Opened.temporary)}}
}
function Inspect-AriaBackup {
 param([string]$Path,[string]$ProtectedPassword,[string]$AdminToken)
 $password=if($ProtectedPassword){[AriaPrivacyCrypto]::Unprotect($ProtectedPassword)}else{''}
 $opened=Open-AriaBackupRead -Path $Path -Password $password -AdminToken $AdminToken
 try{
  $manifest=$opened.manifest
  $id=[guid]::NewGuid().ToString('N');$folder=Join-Path (Get-AriaBackupRoot) 'plans';[void][IO.Directory]::CreateDirectory($folder)
  Write-DreamHubJson (Join-Path $folder ($id+'.json')) @{id=$id;path=[IO.Path]::GetFullPath($Path);sha256=(Get-FileHash -LiteralPath $Path).Hash;protectedPassword=$ProtectedPassword;scope=$manifest.scope;expires=[DateTime]::UtcNow.AddMinutes(30).ToString('o')}
  return [pscustomobject]@{planId=$id;scope=$manifest.scope;skinCount=@($manifest.skinIds).Count;sizeMB=[Math]::Round($manifest.totalBytes/1MB,1);settingsCount=@($manifest.files|Where-Object path -Like 'settings/*').Count}
 }finally{Close-AriaBackupRead $opened;$password=''}
}
function Read-AriaRestoreSettings {
 param([string]$Root,[string]$Name,$Default)
 $path=Join-Path $Root ('settings\'+$Name)
 return ,(Read-AriaBackupJson -Path $path -Default $Default)
}
function Test-AriaRestoredPackageEqual {
 param([string]$Directory,[object[]]$Files,[string]$Id)
 foreach($file in $Files){
  if(-not $file.path.StartsWith(('skins/'+$Id+'/'),[StringComparison]::Ordinal)){continue}
  $relative=$file.path.Substring(('skins/'+$Id+'/').Length).Replace('/','\');$path=Join-Path $Directory $relative
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $false}
  Assert-DreamSkinNoReparseComponents $path
  if((Get-Item -LiteralPath $path).Length -ne $file.size -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $file.sha256){return $false}
 }
 return $true
}
function Restore-AriaBackup {
 param([ValidatePattern('^[a-f0-9]{32}$')][string]$PlanId,[switch]$ApplySettings,[string]$AdminToken)
 $backupRoot=Get-AriaBackupRoot;$planPath=Join-Path (Join-Path $backupRoot 'plans') ($PlanId+'.json')
 Assert-DreamSkinNoReparseComponents $planPath;$plan=Read-DreamHubJson $planPath $null
 if(-not $plan -or [DateTime]::Parse($plan.expires).ToUniversalTime() -lt [DateTime]::UtcNow){throw '恢复预览已过期，请重新选择备份。'}
 if($plan.scope -eq 'private'){Assert-AriaPrivateBackupAccess $AdminToken}
 if((Get-FileHash -LiteralPath $plan.path).Hash -cne $plan.sha256){throw '备份文件在预览后发生变化，请重新检查。'}
 $password=if($plan.protectedPassword){[AriaPrivacyCrypto]::Unprotect($plan.protectedPassword)}else{''}
 $opened=$null;$stage=Join-Path $backupRoot ('.restore-work-'+[guid]::NewGuid().ToString('N'));$guard=$null;$importMutex=$null;$ownsImport=$false;$moved=@();$committed=$false
 try{
  $opened=Open-AriaBackupRead -Path $plan.path -Password $password -AdminToken $AdminToken;$manifest=$opened.manifest
  if($manifest.scope -cne $plan.scope){throw '备份类型发生变化，请重新检查。'}
  Assert-DreamSkinNoReparseComponents $stage;[void][IO.Directory]::CreateDirectory($stage)
  foreach($record in @($manifest.files)){
   $target=[IO.Path]::GetFullPath((Join-Path $stage $record.path.Replace('/','\')))
   if(-not(Test-DreamSkinPathWithin $target $stage)){throw '备份文件越出了恢复目录。'}
   Assert-DreamSkinNoReparseComponents $target;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
   $source=$opened.archive.GetEntry($record.path).Open();$destination=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try{$copied=Copy-AriaArchiveStream $source $destination ([long]$record.size)}finally{$source.Dispose();$destination.Dispose()}
   if($copied.size -ne $record.size -or $copied.sha256 -cne $record.sha256){throw '备份文件完整性检查未通过。'}
  }
  Close-AriaBackupRead $opened;$opened=$null;$password=''
  $loadedThemes=@();$node=Get-DreamSkinNodeRuntime
  foreach($id in @($manifest.skinIds)){
   $directory=Join-Path (Join-Path $stage 'skins') $id
   $loaded=Read-DreamSkinTheme $directory
   if($loaded.Theme.id -cne $id){throw '主题编号与备份清单不一致。'}
   $validation=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList @((Join-Path $PSScriptRoot 'validate-backup-theme.mjs'),$directory) -SeparateStderr
   if($validation.ExitCode -ne 0){throw ('主题内容未通过检查：'+($validation.ErrorOutput -join ' '))}
   $loadedThemes+=@($loaded)
  }
  $incomingMeta=Read-AriaRestoreSettings $stage 'library-meta.json' ([pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}})
  if($incomingMeta.schemaVersion -ne 1 -or -not $incomingMeta.themes){throw '备份收藏资料无效。'}
  $incomingPrompts=Read-AriaRestoreSettings $stage 'prompts.json' @()
  $incomingFavorites=Read-AriaRestoreSettings $stage 'favorites.json' @()
  $incomingPrefs=Read-AriaRestoreSettings $stage 'theme-preferences.json' ([pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}})
  $optional=@{}
  if($ApplySettings -and $manifest.scope -eq 'public'){
   $p=Read-AriaRestoreSettings $stage 'playback-settings.json' $null
   if($p){if($p.schemaVersion -ne 1 -or $p.mode -notin @('normal','battery','static')){throw '备份播放策略无效。'};$optional['playback-settings.json']=$p}
   $p=Read-AriaRestoreSettings $stage 'import-policy.json' $null
   if($p){if([int]$p.videoMaxMB -notin @(64,128,256) -or [int]$p.sceneMaxMB -notin @(128,256,512)){throw '备份导入规则无效。'};$optional['import-policy.json']=[pscustomobject]@{videoMaxMB=[int]$p.videoMaxMB;sceneMaxMB=[int]$p.sceneMaxMB;autoImportWorkshop=[bool]$p.autoImportWorkshop;recordSeconds=if([int]$p.recordSeconds -ge 10 -and [int]$p.recordSeconds -le 60){[int]$p.recordSeconds}else{20}}}
   $p=Read-AriaRestoreSettings $stage 'window-settings.json' $null
   if($p){if([int]$p.width -lt 1060 -or [int]$p.width -gt 4096 -or [int]$p.height -lt 760 -or [int]$p.height -gt 4096 -or $p.state -notin @('normal','maximized')){throw '备份窗口偏好无效。'};$optional['window-settings.json']=[pscustomobject]@{remember=[bool]$p.remember;width=[int]$p.width;height=[int]$p.height;state=[string]$p.state}}
  }
  $guard=Enter-DreamSkinOperationLock -TimeoutMilliseconds 8000
  $importMutex=New-DreamSkinThemeImportMutex;try{$ownsImport=$importMutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$ownsImport=$true}
  if(-not $ownsImport){throw '皮肤库正在保存其他内容，请稍后重试恢复。'}
  if($manifest.scope -eq 'private'){Assert-AriaPrivateBackupAccess $AdminToken}
  $existing=@{};foreach($entry in @(Get-DreamSkinSavedThemes -SkipImageMetadata)){$existing[$entry.Id]=$entry.Path}
  $hidden=@(Get-AriaHiddenIds);$map=@{};$duplicates=@{};$new=@();$library=Join-Path $script:DreamHubHome 'themes'
  Assert-DreamSkinNoReparseComponents $library;[void][IO.Directory]::CreateDirectory($library)
  foreach($loaded in $loadedThemes){
   $old=[string]$loaded.Theme.id;$sameScope=($old -in $hidden) -eq ($manifest.scope -eq 'private')
   if($existing.ContainsKey($old) -and $sameScope -and (Test-AriaRestoredPackageEqual $existing[$old] @($manifest.files) $old)){$map[$old]=$old;$duplicates[$old]=$true;continue}
   $id=$old
   if($existing.ContainsKey($old) -or (Test-Path -LiteralPath (Join-Path $library $id))){$id='restored-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12);$loaded.Theme.id=$id;Write-DreamSkinTheme $loaded.Directory $loaded.Theme}
   $target=Join-Path $library $id;Assert-DreamSkinNoReparseComponents $target
   if(-not(Test-DreamSkinThemePathWithin $loaded.Directory $stage) -or -not(Test-DreamSkinPathWithin $target $library)){throw '恢复目录越界，原皮肤已保留。'}
   $map[$old]=$id;$new+=@([pscustomobject]@{source=$loaded.Directory;target=$target;id=$id})
  }
  $currentMeta=Get-AriaLibraryMeta;$meta=($currentMeta|ConvertTo-Json -Depth 14)|ConvertFrom-Json
  foreach($old in $map.Keys){
   $previousMeta=$meta.themes.PSObject.Properties[$map[$old]].Value
   $hasCustom=$previousMeta -and @($previousMeta.PSObject.Properties|Where-Object Name -in @('name','group','tags')).Count
   if($duplicates.ContainsKey($old) -and $hasCustom){continue}
   $item=$incomingMeta.themes.PSObject.Properties[$old].Value
   if($item){
    $name=([string]$item.name).Trim();$group=([string]$item.group).Trim();$tags=@($item.tags|Where-Object {$_}|Select-Object -Unique)
    if($name.Length -gt 70 -or $group.Length -gt 30 -or $tags.Count -gt 12 -or @($tags|Where-Object {([string]$_).Length -gt 20}).Count){throw '备份名称、分组或标签超出长度限制。'}
    $restoredMeta=[pscustomobject]@{name=$name;group=$group;tags=@($tags)}
    $lastUsed=@()
    foreach($stamp in @($item.lastUsed,$previousMeta.lastUsed)){
     $parsed=[DateTimeOffset]::MinValue
     if($stamp -and ([string]$stamp).Length -le 64 -and [DateTimeOffset]::TryParse([string]$stamp,[ref]$parsed)){$lastUsed+=@($parsed.ToUniversalTime())}
    }
    if($lastUsed.Count){$restoredMeta|Add-Member lastUsed (($lastUsed|Sort-Object -Descending|Select-Object -First 1).ToString('o'))}
    $meta.themes|Add-Member -NotePropertyName $map[$old] -NotePropertyValue $restoredMeta -Force
   }
  }
  $favorites=@(Read-DreamHubJson (Join-Path $script:DreamHubHome 'favorites.json') @())
  if($manifest.scope -eq 'public'){foreach($old in @($incomingFavorites)){if($map.ContainsKey([string]$old)){$favorites+=@($map[[string]$old])}};$favorites=@($favorites|Select-Object -Unique)}
  $prompts=@(Read-DreamHubJson (Join-Path $script:DreamHubHome 'prompts.json') @())
  if($manifest.scope -eq 'public'){
   if(@($incomingPrompts).Count -gt 200){throw '备份提示词数量超出限制。'}
   foreach($prompt in @($incomingPrompts)){
    if(-not $prompt.name -or -not $prompt.text -or ([string]$prompt.name).Length -gt 80 -or ([string]$prompt.text).Length -gt 10000){throw '备份提示词格式无效。'}
    $same=@($prompts|Where-Object { $_.id -ceq $prompt.id -and $_.text -ceq $prompt.text -and $_.name -ceq $prompt.name });if($same.Count){continue}
    $copy=($prompt|ConvertTo-Json -Depth 8)|ConvertFrom-Json
    if($copy.id -cnotmatch '^prompt-[a-f0-9]{32}$' -or @($prompts|Where-Object id -ceq $copy.id).Count){$copy|Add-Member id ('prompt-'+[guid]::NewGuid().ToString('N')) -Force}
    if($copy.sceneThemeId){$copy.sceneThemeId=if($map.ContainsKey([string]$copy.sceneThemeId)){$map[[string]$copy.sceneThemeId]}else{''}}
    if($null -ne $copy.sceneOpacity -and ([int]$copy.sceneOpacity -lt 0 -or [int]$copy.sceneOpacity -gt 100)){throw '备份提示词透明度无效。'}
    $prompts+=@($copy)
   }
  }
  $preferences=Read-DreamHubJson (Join-Path $script:DreamHubState 'theme-preferences.json') ([pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}})
  if(-not $preferences.themes){$preferences=[pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}}}
  $active=Read-DreamHubJson (Join-Path $script:DreamHubState 'active-theme\theme.json') $null
  foreach($old in $map.Keys){
   if($duplicates.ContainsKey($old) -or $map[$old] -ceq $active.id){continue}
   $p=$incomingPrefs.themes.PSObject.Properties[$old].Value;if(-not $p){continue}
   $clean=[pscustomobject]@{}
   if($null -ne $p.transparency){if([int]$p.transparency -lt 0 -or [int]$p.transparency -gt 100){throw '备份不透明度无效。'};$clean|Add-Member transparency ([int]$p.transparency)}
   if($p.displayMode){if($p.displayMode -notin @('cover','contain','native')){throw '备份显示方式无效。'};$clean|Add-Member displayMode ([string]$p.displayMode)}
   $preferences.themes|Add-Member -NotePropertyName $map[$old] -NotePropertyValue $clean -Force
  }
  $snapshot=Join-Path $backupRoot ('before-restore-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($snapshot)
  foreach($name in @('library-meta.json','favorites.json','prompts.json')+@($optional.Keys)){
   $path=Join-Path $script:DreamHubHome $name;if(Test-Path -LiteralPath $path){Assert-DreamSkinNoReparseComponents $path;[IO.File]::Copy($path,(Join-Path $snapshot $name))}
  }
  $prefPath=Join-Path $script:DreamHubState 'theme-preferences.json';if(Test-Path -LiteralPath $prefPath){[IO.File]::Copy($prefPath,(Join-Path $snapshot 'theme-preferences.json'))}
  if($manifest.scope -eq 'private'){
   $vaultPath=Join-Path $script:AriaPrivacyRoot 'vault.dat';[IO.File]::Copy($vaultPath,(Join-Path $snapshot 'vault.dat'))
   $vault=Get-AriaPrivacyConfig;$vault.hiddenIds=@(@($vault.hiddenIds)+@($map.Values)|Select-Object -Unique);Write-AriaPrivacyConfig $vault
  }
  # Mark private IDs before making any new directory visible to library scans.
  foreach($item in $new){Move-Item -LiteralPath $item.source -Destination $item.target -ErrorAction Stop;$moved+=@($item.target)}
  Write-DreamHubJson (Join-Path $script:DreamHubHome 'library-meta.json') $meta
  if($manifest.scope -eq 'public'){Write-DreamHubJson (Join-Path $script:DreamHubHome 'favorites.json') @($favorites);Write-DreamHubJson (Join-Path $script:DreamHubHome 'prompts.json') @($prompts)}
  Write-DreamHubJson $prefPath $preferences
  foreach($name in $optional.Keys){Write-DreamHubJson (Join-Path $script:DreamHubHome $name) $optional[$name]}
  $committed=$true;[IO.File]::Delete($planPath)
  return [pscustomobject]@{restored=$new.Count;alreadyPresent=$duplicates.Count;scope=$manifest.scope;message=('恢复完成：新增 '+$new.Count+' 张，已有 '+$duplicates.Count+' 张已保留。当前背景未切换；原设置已另存备份。')}
 }catch{
  if($moved.Count){throw ('恢复未全部完成，已保留 '+$moved.Count+' 张有效皮肤和原设置备份，请重新检查后继续：'+$_.Exception.Message)}
  throw
 }finally{
  if($opened){Close-AriaBackupRead $opened}
  if($ownsImport){$importMutex.ReleaseMutex()};if($importMutex){$importMutex.Dispose()}
  if($guard){Exit-DreamSkinOperationLock $guard}
  if(Test-Path -LiteralPath $stage){Remove-DreamSkinManagedDirectoryVerified -Path $stage -Root $backupRoot}
 }
}

function Show-AriaBackupFileDialog {
 param([switch]$Private,[switch]$Save)
 $dialog=if($Save){[Windows.Forms.SaveFileDialog]::new()}else{[Windows.Forms.OpenFileDialog]::new()}
 $dialog.InitialDirectory=Get-AriaBackupRoot;$dialog.Filter=if($Private){'Aria 加密备份|*.ariavault'}else{'Aria 备份|*.zip'}
 $dialog.DefaultExt=if($Private){'ariavault'}else{'zip'}
 if($Save){$dialog.AddExtension=$true;$dialog.OverwritePrompt=$true;$dialog.FileName='Aria-'+$(if($Private){'private-'}else{''})+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.'+$dialog.DefaultExt}
 try{if($dialog.ShowDialog($script:HubForm) -eq 'OK'){return $dialog.FileName};return ''}finally{$dialog.Dispose()}
}
