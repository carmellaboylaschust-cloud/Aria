
param([string]$RequestPath,[string]$ResultPath,[switch]$Worker,[int]$OwnerPid,[string]$OwnerStarted,[ValidatePattern('^[a-f0-9]{32}$')][string]$QueueToken)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'background-library.ps1')
. (Join-Path $PSScriptRoot 'scene-queue.ps1')
. (Join-Path $PSScriptRoot 'hub-workshop.ps1')
. (Join-Path $PSScriptRoot 'hub-data.ps1')
. (Join-Path $PSScriptRoot 'hub-feed.ps1')
function Invoke-AriaActionRequest {
 param([string]$RequestPath,[string]$ResultPath)
$requests=Join-Path $script:DreamHubHome 'requests'
if(-not(Test-DreamSkinPathWithin $RequestPath $requests) -or -not(Test-DreamSkinPathWithin $ResultPath $requests)){throw '请求路径无效。'}
Assert-DreamSkinNoReparseComponents $RequestPath;Assert-DreamSkinNoReparseComponents $ResultPath
$request=Read-DreamHubJson $RequestPath $null
$script:AriaRequestHiddenToken=[string]$request.ariaHiddenAccess
$result=[ordered]@{id=$request.id;ok=$true}
try{
  switch($request.action){
    'prepare' {Initialize-DreamHubThumbnails}
    'exportBackup' {. (Join-Path $PSScriptRoot 'hub-backup.ps1');$password=if($request.protectedPassword){[AriaPrivacyCrypto]::Unprotect($request.protectedPassword)}else{''};try{$backup=Export-AriaBackup -Path $request.path -Scope $request.scope -Password $password -AdminToken $request.ariaAdminAccess;$result.message=$backup.message}finally{$password=''}}
    'inspectBackup' {. (Join-Path $PSScriptRoot 'hub-backup.ps1');$preview=Inspect-AriaBackup -Path $request.path -ProtectedPassword $request.protectedPassword -AdminToken $request.ariaAdminAccess;foreach($property in $preview.PSObject.Properties){$result[$property.Name]=$property.Value}}
    'restoreBackup' {. (Join-Path $PSScriptRoot 'hub-backup.ps1');$backup=Restore-AriaBackup -PlanId $request.planId -ApplySettings:([bool]$request.applySettings) -AdminToken $request.ariaAdminAccess;$result.message=$backup.message}
    'storageOverview' {. (Join-Path $PSScriptRoot 'hub-backup.ps1');. (Join-Path $PSScriptRoot 'hub-storage.ps1');$result.overview=Get-AriaStorageOverview}
    'storageCleanup' {. (Join-Path $PSScriptRoot 'hub-backup.ps1');. (Join-Path $PSScriptRoot 'hub-storage.ps1');$clean=Clear-AriaStoragePlan -PlanId $request.planId;$result.message=$clean.message}
    'browseDownloaded' {$result.items=@(Get-AriaDownloadedWallpapers)}
    'saveWuwaImage' {. (Join-Path $PSScriptRoot 'hub-wuwa-media.ps1');$import=Save-AriaWuwaImage -Url $request.url -Title $request.title -SourcePage $request.sourcePage;$result.message=$import.message;$result.themeId=$import.themeId}
    'importWuwaDownload' {. (Join-Path $PSScriptRoot 'hub-wuwa-media.ps1');$import=Import-AriaWuwaDownload -Path $request.path -Title $request.title -SourcePage $request.sourcePage;$result.message=$import.message;$result.themeId=$import.themeId}
    'saveLibraryMeta' {$libraryArgs=@{Ids=@($request.themeIds);Group=[string]$request.group;Tags=@($request.tags)};if($request.rename){if($libraryArgs.Ids.Count -ne 1){throw '请逐张修改皮肤名称。'};$libraryArgs.Name=[string]$request.name};Set-AriaLibraryMeta @libraryArgs;$result.message='皮肤资料已保存'}
    'workshopBatch' {
      $ids=@($request.workshopIds|Select-Object -Unique);if(-not $ids.Count -or $ids.Count -gt 20){throw '每次可导入 1 至 20 张壁纸。'}
      $messages=@();$accepted=0
      foreach($id in $ids){try{$null=Add-DreamHubWorkshopJob -Id $id -Seconds (Get-DreamHubPolicy).recordSeconds;$accepted++}catch{$messages+=@($id+'：'+$_.Exception.Message)}}
      $result.message='已加入 '+$accepted+' 个导入任务'+$(if($messages.Count){'；'+($messages -join '；')}else{''})
    }
    'addMedia' {
      $messages=@()
      foreach($path in @($request.paths)){
        try{$import=Import-DreamSkinLocalMedia -Path $path;if($import.Theme.id -in @(Get-AriaHiddenIds) -and -not(Test-AriaGrant -Role hidden)){$messages+='皮肤库中已有隐藏副本，可解锁后管理。'}else{$messages+=$(if($import.AlreadyExists){'已有相同图片：'}else{'已加入：'})+$import.Theme.name}}catch{$messages+=[IO.Path]::GetFileName($path)+'：'+$_.Exception.Message}
      }
      $result.message=$messages -join [Environment]::NewLine
      Initialize-DreamHubThumbnails
    }
    'uninstallThemes' {$uninstall=Remove-DreamHubThemes -Ids @($request.themeIds);$result.message=$uninstall.message;$result.removedIds=@($uninstall.removedIds)}
    'record' {
      $loaded=Get-DreamHubThemeById $request.themeId
      if(-not $loaded.Theme.sourceSceneProject){throw '此皮肤没有可重新录制的 Scene / Web 项目。'}
      $null=Add-DreamSceneJob -ProjectPath $loaded.Theme.sourceSceneProject -Seconds ([int]$request.seconds)
      $result.message='已加入 1080p 录制任务'
    }
    'addScene' {$null=Add-DreamSceneJob -ProjectPath $request.path -Seconds ([int]$request.seconds);$result.message='已加入后台任务'}
    'workshopImport' {$null=Add-DreamHubWorkshopJob -Id $request.workshopId -Seconds (Get-DreamHubPolicy).recordSeconds;$result.message='已加入任务；下载完成后自动处理'}
    'importHero' {
      $import=Save-DreamHubHero -Index ([int]$request.index) -HeroId ([string]$request.heroId)
      $result.message='已永久保存到「我的壁纸」，并加入皮肤库'
    }
    'cancelJob' {Stop-DreamSceneJob $request.jobId;$result.message='已提交取消'}
    'retryJob' {
      $job=Read-DreamHubJson (Get-DreamSceneJobPath $request.jobId) $null
      if(-not $job -or ($job.status -notin @('failed','cancelled') -and -not($job.kind -eq 'workshop' -and $job.status -eq 'waiting-download'))){throw '这个任务暂时不能重试。'}
      if($job.kind -eq 'workshop'){$null=Add-DreamHubWorkshopJob $job.workshopId ([int]$job.seconds)}
      else{$null=Add-DreamSceneJob -ProjectPath $job.projectPath -Seconds ([int]$job.seconds) -Appearance $job.appearance}
      $result.message='已重新排队'
    }
    'launch' {
      $loaded=Get-DreamHubThemeById $request.themeId
      $prompt="$($request.prompt)"
      if($prompt.Length -gt 16000){throw '本次提示词过长。'}
      if($null -ne $request.sceneOpacity){Set-DreamSkinLocalOpacity -ThemeId $request.themeId -Opacity $request.sceneOpacity}
      $token=[guid]::NewGuid().ToString('N')
      . (Join-Path $PSScriptRoot 'apply-or-start.ps1') -SavedThemeDirectory $loaded.Directory -ResultToken $token
      $check=Read-DreamSkinStartResult -StateRoot $script:DreamHubState -Token $token
      if($check.outcome -ne 'success'){throw ('桌面端未启动成功：'+$check.category)}
      $state=Read-DreamSkinState -Path (Join-Path $script:DreamHubState 'state.json');$codex=Get-DreamSkinCodexInstallFromState $state;if($codex){[void](Invoke-DreamSkinCodexWindowActivation -Codex $codex)}
      if($prompt){
        $deepLink='codex://new?prompt='+[Uri]::EscapeDataString($prompt)
        $info=[Diagnostics.ProcessStartInfo]::new($deepLink);$info.UseShellExecute=$true
        $child=[Diagnostics.Process]::Start($info);if($child){$child.Dispose()}
      }
      $usageWarning='';try{Set-AriaLibraryMeta -Ids @($request.themeId) -RecordUse}catch{$usageWarning='；本次使用记录未能保存，背景已正常应用'}
      $result.message=if($prompt){'已打开本次工作的输入框，确认后发送即可'}else{'皮肤已即时切换，桌面端无需重启'}
      if($request.privacyMode){$result.message='已换回普通背景，隐藏列表已锁定'}
      $result.message+=$usageWarning
    }
    default {throw '不支持此操作。'}
  }
}catch{$result.ok=$false;$result.error=$_.Exception.Message;$result.details=($_|Out-String)+[Environment]::NewLine+$_.ScriptStackTrace}
try{Write-DreamHubJson $ResultPath $result}finally{if(Test-Path -LiteralPath $RequestPath){[IO.File]::Delete($RequestPath)}}

}
if(-not $Worker){Invoke-AriaActionRequest -RequestPath $RequestPath -ResultPath $ResultPath;exit 0}
if($OwnerPid -le 0 -or -not $OwnerStarted -or -not $QueueToken){throw '后台连接缺少所属窗口信息。'}
$queueRoot=Join-Path $script:DreamHubHome 'requests'
$workerMutex=[Threading.Mutex]::new($false,('Local\Aria.LaunchWorker.'+$QueueToken));$workerOwns=$false
try{
 try{$workerOwns=$workerMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$workerOwns=$true}
 if(-not $workerOwns){exit 0}
 try{$null=Get-DreamSkinNodeRuntime;$null=Get-DreamSkinRegisteredCodexInstalls}catch{}
 while($true){
  $owner=$null
  try{$owner=[Diagnostics.Process]::GetProcessById($OwnerPid);if($owner.StartTime.ToUniversalTime().ToString('o') -cne $OwnerStarted){break}}catch{break}finally{if($owner){$owner.Dispose()}}
  foreach($queueEntry in @(Get-ChildItem -LiteralPath $queueRoot -Filter ('*.'+$QueueToken+'.launch.request.json') -File|Sort-Object CreationTimeUtc)){
   if($queueEntry.Name -cnotmatch ('^[a-f0-9]{32}\.'+[regex]::Escape($QueueToken)+'\.launch\.request\.json$')){continue}
   $responsePath=$queueEntry.FullName.Replace('.request.json','.result.json')
   $claimed=$queueEntry.FullName.Replace('.request.json','.processing.json')
   try{Assert-DreamSkinNoReparseComponents $queueEntry.FullName;Assert-DreamSkinNoReparseComponents $claimed;[IO.File]::Move($queueEntry.FullName,$claimed)}catch{continue}
   Invoke-AriaActionRequest -RequestPath $claimed -ResultPath $responsePath
  }
  Start-Sleep -Milliseconds 250
 }
}finally{if($workerOwns){$workerMutex.ReleaseMutex()};$workerMutex.Dispose()}
