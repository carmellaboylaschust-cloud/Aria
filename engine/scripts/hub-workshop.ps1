
function Get-AriaWorkshopSourceRevision {
 param([string]$ProjectPath,[switch]$Details)
 $folder=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ProjectPath));Assert-DreamSkinNoReparseComponents $folder
 $rows=[Collections.Generic.List[string]]::new();$latest=[DateTime]::MinValue
 foreach($file in @(Get-DreamHubProjectFiles $ProjectPath|Sort-Object FullName)){
  Assert-DreamSkinNoReparseComponents $file.FullName
  $rows.Add($file.FullName.Substring($folder.Length).ToLowerInvariant()+'|'+$file.Length+'|'+$file.LastWriteTimeUtc.Ticks)
  if($file.LastWriteTimeUtc -gt $latest){$latest=$file.LastWriteTimeUtc}
 }
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($rows -join [Environment]::NewLine)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 if($Details){return [pscustomobject]@{revision=$hash;latestWrite=$latest}}
 return $hash
}
function Find-AriaWorkshopImportedTheme {
 param([string]$Id,$Details,[int]$Seconds=20)
 if(-not $Details){return $null}
 $source=Get-AriaWorkshopSourceRevision $Details.Path -Details
 $jobs=@(Get-DreamSceneJobs|Where-Object {$_.workshopId -ceq $Id -and $_.status -eq 'completed' -and $_.themeDirectory}|Sort-Object updatedAt -Descending)
 $candidates=[Collections.Generic.List[object]]::new();$seen=@{}
 foreach($job in $jobs){$candidates.Add([pscustomobject]@{path=$job.themeDirectory;job=$job})}
 foreach($entry in @(Get-DreamSkinSavedThemes -SkipImageMetadata)){$candidates.Add([pscustomobject]@{path=$entry.Path;job=$null})}
 foreach($candidate in $candidates){
  if($seen.ContainsKey($candidate.path)){continue};$seen[$candidate.path]=$true
  try{
   $allowed=$false;foreach($managedRoot in @('D:\Aria\user-backgrounds\themes','D:\Aria\runtime\themes')){if(Test-DreamSkinThemePathWithin $candidate.path $managedRoot){$allowed=$true}}
   if(-not $allowed){continue}
   $loaded=Read-DreamSkinTheme $candidate.path -SkipImageMetadata
   if(-not $candidate.job -and $loaded.Theme.sourceWorkshopId -cne $Id -and $loaded.Theme.sourceSceneProject -ine $Details.Path){continue}
   $revision=[string]$loaded.Theme.sourceWorkshopRevision
   if($revision){if($revision -cne $source.revision){continue}}
   else{
    $importedAt=if($candidate.job.updatedAt){[DateTime]::Parse($candidate.job.updatedAt).ToUniversalTime()}else{(Get-Item -LiteralPath (Join-Path $loaded.Directory 'theme.json')).LastWriteTimeUtc}
    if($source.latestWrite -gt $importedAt){continue}
   }
   if([IO.Path]::GetExtension($loaded.ImagePath) -notin @('.mp4','.webm')){continue}
   Assert-DreamHubMediaPolicy $loaded.ImagePath
   $probe=Invoke-DreamSkinNative -FilePath (Join-Path $script:DreamSceneTools 'bin\ffprobe.exe') -ArgumentList @('-v','error','-select_streams','v:0','-show_entries','stream=width,height:format=duration','-of','json',$loaded.ImagePath) -SeparateStderr
   if($probe.ExitCode -ne 0){continue};$meta=($probe.Output -join [Environment]::NewLine)|ConvertFrom-Json
   if(-not $meta.streams.Count -or [double]$meta.format.duration -le 0){continue}
   if($Details.Type -in @('scene','web') -and ($meta.streams[0].width -ne 1920 -or $meta.streams[0].height -ne 1080 -or [double]$meta.format.duration -lt ($Seconds-0.5))){continue}
   return $loaded
  }catch{continue}
 }
 return $null
}
function Complete-AriaWorkshopJobFromTheme {
 param($Job,$Imported)
 $Job.themeId=$Imported.Theme.id;$Job.themeDirectory=$Imported.Directory;$Job.outputPath=$Imported.ImagePath
 $Job.status='completed';$Job.percent=100;$Job.error='';$Job.message='皮肤已入库，已核对任务状态'
 $Job|Add-Member -NotePropertyName reusedImport -NotePropertyValue $true -Force
 Save-DreamSceneJob $Job
}
function Repair-AriaWorkshopImportResults {
 $guard=Enter-DreamSceneMutex 'Queue' 1000;if(-not $guard){return 0}
 $repaired=0
 try{
  foreach($job in @(Get-DreamSceneJobs|Where-Object {$_.kind -eq 'workshop' -and $_.status -eq 'failed' -and $_.projectPath})){
   try{$details=Read-DreamHubWorkshopProject $job.projectPath;$imported=Find-AriaWorkshopImportedTheme -Id $job.workshopId -Details $details -Seconds $job.seconds;if($imported){Complete-AriaWorkshopJobFromTheme $job $imported;$repaired++}}catch{}
  }
 }finally{Exit-DreamSceneMutex $guard}
 return $repaired
}

function Start-DreamHubSteamDownloadService {
 $steamRoot=Get-AriaSteamRoot;if(-not $steamRoot){throw '请先通过 Steam 官方安装程序准备客户端。'}
 $steam=Join-Path $steamRoot 'steam.exe'
 foreach($process in @(Get-Process -Name steam -ErrorAction SilentlyContinue)){
  try{if(Test-DreamSkinPathEqual -Left $process.Path -Right $steam){return}}catch{}
 }
 Assert-DreamSkinNoReparseComponents $steam
 if(-not(Test-Path -LiteralPath $steam -PathType Leaf)){throw '找不到 Steam 客户端，请先安装或打开已有的 Steam。'}
 $signature=Get-AuthenticodeSignature -LiteralPath $steam
 if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Valve'){throw 'Steam 启动文件校验未通过，已保留下载任务。'}
 $info=[Diagnostics.ProcessStartInfo]::new($steam);$info.Arguments='-silent';$info.WorkingDirectory=Split-Path $steam;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
 $process=[Diagnostics.Process]::Start($info);if($process){$process.Dispose()}
}


function Get-DreamHubWorkshopRoots {
  $steamRoot=Get-AriaSteamRoot;if(-not $steamRoot){return @()}
  $roots=@((Join-Path $steamRoot 'steamapps\workshop\content\431960'))
  $vdf=Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
  if(Test-Path -LiteralPath $vdf){
    foreach($match in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s+"([^"]+)"')){
      $base=$match.Groups[1].Value.Replace('\\','\')
      $roots+=Join-Path $base 'steamapps\workshop\content\431960'
    }
  }
  @($roots|Select-Object -Unique|Where-Object {Test-Path -LiteralPath $_ -PathType Container})
}
function Find-DreamHubWorkshopProject {
  param([string]$Id)
  if($Id -cnotmatch '^[0-9]{6,12}$'){throw '壁纸编号无效。'}
  foreach($root in Get-DreamHubWorkshopRoots){
    $project=Join-Path (Join-Path $root $Id) 'project.json'
    if((Test-Path -LiteralPath $project -PathType Leaf) -and (Test-DreamHubWorkshopReady $root $Id)){return $project}
  }
  return $null
}
function Read-DreamHubWorkshopProject {
  param([string]$Path)
  $full=[IO.Path]::GetFullPath($Path);Assert-DreamSkinNoReparseComponents $full
  if([IO.Path]::GetFileName($full) -ine 'project.json' -or (Get-Item -LiteralPath $full).Length -gt 2MB){throw '壁纸说明文件无效。'}
  $data=Get-Content -LiteralPath $full -Raw -Encoding UTF8|ConvertFrom-Json
  $folder=[IO.Path]::GetDirectoryName($full)
  $type=([string]$data.type).ToLowerInvariant()
  if($type -notin @('scene','video','web')){throw '此壁纸类型不允许自动导入：只接受视频、Scene 场景和 Web 网页。'}
  $name="$($data.title)".Trim();if(-not $name){$name=Split-Path $folder -Leaf}
  if($name.Length -gt 70){$name=$name.Substring(0,70)}
  $media=$null
  if($type -eq 'video'){
    if(-not $data.file -or [IO.Path]::IsPathRooted("$($data.file)")){throw '视频路径无效。'}
    $media=[IO.Path]::GetFullPath((Join-Path $folder "$($data.file)"))
    if(-not(Test-DreamSkinThemePathWithin $media $folder)){throw '视频路径超出了壁纸目录。'}
    Assert-DreamHubMediaPolicy $media
  }else{$null=Read-DreamSceneProject $full;Assert-DreamHubScenePolicy $full}
  [pscustomobject]@{Path=$full;Name=$name;Type=$type;Media=$media}
}
function Add-DreamHubWorkshopJob {
  param([string]$Id,[int]$Seconds=20)
  if($Id -cnotmatch '^[0-9]{6,12}$'){throw '请先打开一张具体的创意工坊壁纸，再点击导入。'}
  if($Seconds -notin @(10,20,30,60)){throw '录制时长无效。'}
  Assert-DreamHubFreeSpace;Initialize-DreamSceneQueue
  $guard=Enter-DreamSceneMutex 'Queue'
  if(-not $guard){throw '任务列表正忙，请稍后重试。'}
  try{
    $existing=@(Get-DreamSceneJobs|Where-Object {$_.workshopId -eq $Id -and $_.status -in @('waiting-download','queued','starting','recording','finalizing')})
    if($existing.Count){if($existing[0].status -eq 'waiting-download'){Start-DreamHubSteamDownloadService;$existing[0].message='正在等待 Steam 后台下载；请确保客户端与商城是同一账号，完成后自动入库。';Save-DreamSceneJob $existing[0]};Start-DreamSceneWorker;return $existing[0]}
    $project=Find-DreamHubWorkshopProject $Id
    $details=if($project){Read-DreamHubWorkshopProject $project}else{$null}
    $imported=if($details){Find-AriaWorkshopImportedTheme -Id $Id -Details $details -Seconds $Seconds}
    if($imported){
      $related=@(Get-DreamSceneJobs|Where-Object {$_.workshopId -ceq $Id -and $_.status -in @('completed','failed','queued','waiting-download')})
      foreach($previous in $related){if($previous.status -ne 'completed'){Complete-AriaWorkshopJobFromTheme $previous $imported}}
      if($related.Count){return $related[-1]}
    }
    if(-not $project){Start-DreamHubSteamDownloadService}
    $job=[pscustomobject]@{
      schemaVersion=1;id=[guid]::NewGuid().ToString('N');kind='workshop';workshopId=$Id
      name=if($details){$details.Name}else{'Steam '+$Id};projectPath=if($project){$project}else{''};projectType=if($details){$details.Type}else{''}
      seconds=$Seconds;appearance='dark';status=if($project){'queued'}else{'waiting-download'};percent=0
      message=if($project){'等待自动导入'}else{'正在等待 Steam 后台下载；请确保客户端与商城是同一账号，下载完成后自动入库。'};createdAt=[DateTime]::UtcNow.ToString('o');updatedAt=''
      outputPath='';themeDirectory='';themeId='';workerPid=0;workerStartedAt='';windowTitle='';error=''
    }
    if($imported){Complete-AriaWorkshopJobFromTheme $job $imported}else{Save-DreamSceneJob $job;Start-DreamSceneWorker};return $job
  }finally{Exit-DreamSceneMutex $guard}
}
function Update-DreamHubWaitingJobs {
  if($script:NextDownloadCheck -and [DateTime]::UtcNow -lt $script:NextDownloadCheck){return}
  $script:NextDownloadCheck=[DateTime]::UtcNow.AddSeconds(3)
  foreach($job in @(Get-DreamSceneJobs|Where-Object {$_.status -eq 'waiting-download'})){
    if(Test-Path -LiteralPath (Get-DreamSceneJobPath $job.id 'cancel')){$job.status='cancelled';$job.message='已取消'}
    elseif(([DateTime]::UtcNow-[DateTime]::Parse($job.createdAt).ToUniversalTime()).TotalHours -ge 24){$job.status='failed';$job.message='等待下载已超过 24 小时，可下载完成后重试。';$job.error=$job.message}
    else{
      $project=Find-DreamHubWorkshopProject $job.workshopId
      if(-not $project){$text=Get-AriaWorkshopDownloadPhase $job.workshopId;if($job.message -cne $text){$job.message=$text;Save-DreamSceneJob $job};continue}
      if(([DateTime]::UtcNow-(Get-Item -LiteralPath $project).LastWriteTimeUtc).TotalSeconds -lt 6){continue}
      try{$details=Read-DreamHubWorkshopProject $project;$job.projectPath=$project;$job.name=$details.Name;$job|Add-Member -NotePropertyName projectType -NotePropertyValue $details.Type -Force;$job.status='queued';$job.message='下载已发现，等待自动导入'}catch{$job.status='failed';$job.message=$_.Exception.Message;$job.error=$job.message}
    }
    Save-DreamSceneJob $job
  }
}
function Invoke-DreamHubWorkshopImport {
  param($Job)
  try{
    if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
    $details=Read-DreamHubWorkshopProject $Job.projectPath
    $imported=Find-AriaWorkshopImportedTheme -Id $Job.workshopId -Details $details -Seconds $Job.seconds
    if($imported){Complete-AriaWorkshopJobFromTheme $Job $imported;return}
    if($details.Type -in @('scene','web')){Invoke-SceneRecording $Job;return}
    $Job.status='finalizing';$Job.percent=50;$Job.message='正在检查视频并加入皮肤库';Save-DreamSceneJob $Job
    $import=Import-DreamSkinLocalMedia -Path $details.Media -Appearance 'dark'
    if(-not $import.AlreadyExists){
      $import.Theme.name=$details.Name+'（Steam 视频）'
      $import.Theme|Add-Member -NotePropertyName sourceWorkshopId -NotePropertyValue $Job.workshopId -Force
      $import.Theme|Add-Member -NotePropertyName sourceWorkshopRevision -NotePropertyValue (Get-AriaWorkshopSourceRevision $details.Path) -Force
      Write-DreamSkinTheme $import.Directory $import.Theme
    }
    $Job.themeId=$import.Theme.id;$Job.themeDirectory=$import.Directory;$Job.outputPath=$import.ImagePath
    $Job.status='completed';$Job.percent=100;$Job.message='视频已加入皮肤库，可选择应用'
  }catch [OperationCanceledException]{$Job.status='cancelled';$Job.message='已取消';$Job.error=''}
  catch{$Job.status='failed';$Job.error=$_.Exception.Message;$Job.message=$Job.error}
  finally{
    if($Job.status -eq 'failed'){
      try{$details=Read-DreamHubWorkshopProject $Job.projectPath;$existingImport=Find-AriaWorkshopImportedTheme -Id $Job.workshopId -Details $details -Seconds $Job.seconds;if($existingImport){Complete-AriaWorkshopJobFromTheme $Job $existingImport}}catch{}
    }
    Save-DreamSceneJob $Job
  }
}


function Test-DreamHubWorkshopReady {
  param([string]$Root,[string]$Id)
  $workshop=Split-Path (Split-Path $Root)
  $manifest=Join-Path $workshop 'appworkshop_431960.acf'
  if(-not(Test-Path -LiteralPath $manifest)){return $false}
  $text=[IO.File]::ReadAllText($manifest)
  $installed=[regex]::Match($text,'(?s)"WorkshopItemsInstalled"\s*\{(?<body>(?:[^{}]|\{[^{}]*\})*)\}')
  if(-not $installed.Success){return $false}
  $item=[regex]::Match($installed.Groups['body'].Value,'(?s)"'+[regex]::Escape($Id)+'"\s*\{(?<body>[^{}]*)\}')
  if(-not $item.Success){return $false}
  $current=[regex]::Match($item.Groups['body'].Value,'"manifest"\s+"(\d+)"')
  if(-not $current.Success){return $false}
  $details=[regex]::Match($text,'(?s)"WorkshopItemDetails"\s*\{(?<body>(?:[^{}]|\{[^{}]*\})*)\}')
  if($details.Success){
    $entry=[regex]::Match($details.Groups['body'].Value,'(?s)"'+[regex]::Escape($Id)+'"\s*\{(?<body>[^{}]*)\}')
    $latest=[regex]::Match($entry.Groups['body'].Value,'"latest_manifest"\s+"(\d+)"')
    if($latest.Success -and $latest.Groups[1].Value -ne $current.Groups[1].Value){return $false}
  }
  $download=Join-Path (Join-Path (Join-Path $workshop 'downloads') '431960') $Id
  return -not(Test-Path -LiteralPath $download)
}


function Get-DreamHubInstalledIds {
  $ids=@()
  foreach($root in Get-DreamHubWorkshopRoots){
    foreach($folder in Get-ChildItem -LiteralPath $root -Directory){
      if($folder.Name -cmatch '^[0-9]{6,12}$' -and (Test-Path -LiteralPath (Join-Path $folder.FullName 'project.json')) -and (Test-DreamHubWorkshopReady $root $folder.Name)){$ids+=$folder.Name}
    }
  }
  @($ids|Select-Object -Unique)
}
function Update-DreamHubWorkshopSubscriptions {
  if(-not (Get-DreamHubPolicy).autoImportWorkshop){return}
  if($script:NextSubscriptionCheck -and [DateTime]::UtcNow -lt $script:NextSubscriptionCheck){return}
  $script:NextSubscriptionCheck=[DateTime]::UtcNow.AddSeconds(20)
  $path=Join-Path $script:DreamHubRoot 'workshop-seen.json'
  $installed=@(Get-DreamHubInstalledIds)
  if(-not(Test-Path -LiteralPath $path)){
    Write-DreamSkinUtf8FileAtomically -Path $path -Content (([pscustomobject]@{schemaVersion=1;ids=$installed}|ConvertTo-Json -Depth 4)+[Environment]::NewLine)
    return
  }
  try{$seenData=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;if($seenData.schemaVersion -ne 1){return};$seen=@($seenData.ids)}catch{return}
  $changed=$false
  foreach($id in $installed){
    if($seen -contains $id){continue}
    $active=@(Get-DreamSceneJobs|Where-Object {$_.status -in @('waiting-download','queued','starting','recording','finalizing')})
    if($active.Count -ge 8){break}
    try{$null=Add-DreamHubWorkshopJob -Id $id -Seconds (Get-DreamHubPolicy).recordSeconds}
    catch{
      $job=[pscustomobject]@{schemaVersion=1;id=[guid]::NewGuid().ToString('N');kind='workshop';workshopId=$id;name='Steam '+$id;projectPath='';seconds=20;appearance='dark';status='failed';percent=0;message=$_.Exception.Message;error=$_.Exception.Message;createdAt=[DateTime]::UtcNow.ToString('o');updatedAt='';outputPath='';themeDirectory='';themeId='';workerPid=0;workerStartedAt='';windowTitle=''}
      Save-DreamSceneJob $job
    }
    $seen+=@($id);$changed=$true
  }
  if($changed){Write-DreamSkinUtf8FileAtomically -Path $path -Content (([pscustomobject]@{schemaVersion=1;ids=$seen}|ConvertTo-Json -Depth 4)+[Environment]::NewLine)}
}

function Get-AriaWorkshopDownloadPhase {
 param([string]$Id)
 if($Id -cnotmatch '^\d{6,12}$'){return '正在等待 Steam 后台下载。'}
 foreach($root in @(Get-DreamHubWorkshopRoots)){
  $workshop=Split-Path (Split-Path $root)
  $download=Join-Path (Join-Path (Join-Path $workshop 'downloads') '431960') $Id
  if(Test-Path -LiteralPath $download -PathType Container){return '已检测到 Steam 下载目录；等待客户端下载完整后自动检查并入库。'}
  if(Test-Path -LiteralPath (Join-Path $root $Id) -PathType Container){return '已检测到部分本地文件，等待 Steam 确认下载完整；完成后自动入库。'}
 }
 return '等待 Steam 后台下载。长时间未变化可点检查下载，并确认客户端与商城登录同一账号。'
}
