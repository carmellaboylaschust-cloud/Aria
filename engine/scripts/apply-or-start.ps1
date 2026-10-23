[CmdletBinding()]
param([string]$SavedThemeDirectory,[switch]$PromptRestart,[ValidatePattern('^[a-f0-9]{32}$')][string]$ResultToken)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
$stateRoot='D:\Aria\runtime'
$stateFile=Join-Path $stateRoot 'state.json'
$watch=[Diagnostics.Stopwatch]::StartNew();$lock=$null;$completed=$false;$snapshot=$null;$wasPaused=$false
$profileSteps=[Collections.Generic.List[object]]::new();$script:profileLast=0
function Add-AriaLaunchTiming([string]$Step){$now=$watch.ElapsedMilliseconds;$profileSteps.Add([pscustomobject]@{step=$Step;ms=($now-$script:profileLast)});$script:profileLast=$now}

try{
 $state=Read-DreamSkinState $stateFile;Add-AriaLaunchTiming 'read-state'
 $node=Get-DreamSkinNodeRuntime;Add-AriaLaunchTiming 'node-validation'
 $codex=if($state){Get-DreamSkinCodexInstallFromState $state};Add-AriaLaunchTiming 'package-validation'
 $identity=if($codex){Get-DreamSkinVerifiedCdpIdentity -Port $state.port -Codex $codex};Add-AriaLaunchTiming 'connection-validation'
 if($identity -and $identity.BrowserId -ceq $state.browserId){
  $lock=Enter-DreamSkinOperationLock -TimeoutMilliseconds 8000
  $latest=Read-DreamSkinState $stateFile
  if($latest.browserId -cne $state.browserId -or $latest.port -ne $state.port){throw '桌面端连接刚刚改变，请再次点击应用。'}
  $state=$latest;Add-AriaLaunchTiming 'operation-lock'
  $paths=Get-DreamSkinThemePaths -StateRoot $stateRoot
  $selected=Read-DreamSkinTheme -ThemeDirectory $SavedThemeDirectory -SkipImageMetadata
  $active=Read-DreamSkinTheme -ThemeDirectory $paths.Active -SkipImageMetadata
  Add-AriaLaunchTiming 'read-selected-theme'
  $started=Get-DreamSkinProcessStartedAt $state.injectorPid
  if(-not $started -or $started -cne $state.injectorStartedAt){
   # Repair only our background watcher; keep the verified Codex session running.
   $injector=Join-Path $PSScriptRoot 'injector.mjs'
   $spawn=Invoke-DreamSkinNative $node.Path @((Join-Path $PSScriptRoot 'start-hidden-watch.mjs'),(Join-Path $stateRoot 'injector.log'),(Join-Path $stateRoot 'injector-error.log'),$injector,'--watch','--port',"$($state.port)",'--browser-id',$state.browserId,'--theme-dir',$paths.Active,'--pause-file',$paths.PauseFile) -SeparateStderr
   if($spawn.ExitCode -ne 0){throw ($spawn.ErrorOutput -join ' ')}
   $child=($spawn.Output -join [Environment]::NewLine)|ConvertFrom-Json
   $started=Get-DreamSkinProcessStartedAt ([int]$child.pid)
   if(-not $started){throw '背景连接未能恢复，桌面端已保留。'}
   $state.injectorPid=[int]$child.pid;$state.injectorStartedAt=$started;$state.injectorPath=$injector;$state.nodePath=$node.Path;$state.nodeVersion=$node.Version
   Write-DreamSkinState $stateFile $state
  }
  Add-AriaLaunchTiming 'watcher-check'
  $wasPaused=Test-DreamSkinPaused -StateRoot $stateRoot
  if($active.Theme.id -cne $selected.Theme.id){
   . (Join-Path $PSScriptRoot 'apply-community-theme.ps1') -FunctionsOnly
   $snapshot=Join-Path $stateRoot ('.quick-switch-'+[guid]::NewGuid().ToString('N'))
   $before=Get-DreamSkinThemeRuntimeContentFingerprint -ThemeDirectory $paths.Active
   $null=Copy-DreamSkinActiveThemeSnapshot -Paths $paths -Destination $snapshot
   $null=Use-DreamSkinSavedTheme -ThemeDirectory $SavedThemeDirectory -StateRoot $stateRoot
  }
  $null=Set-DreamSkinPaused -Paused $false -StateRoot $stateRoot
  # A picker in front can occlude Codex. Verify decoded skin and session identity without requiring foreground visibility.
  Add-AriaLaunchTiming 'theme-apply'
  # Local videos are transferred before the first frame can decode. Budget for file size.
  $readyTimeout=15000
  if([IO.Path]::GetExtension($selected.ImagePath).ToLowerInvariant() -in @('.mp4','.webm')){
   $videoBytes=(Get-Item -LiteralPath $selected.ImagePath).Length
   $readyTimeout=[int][Math]::Min(180000,60000+[Math]::Ceiling($videoBytes/1MB)*250)
  }
  $check=Invoke-DreamSkinNative $node.Path @((Join-Path $PSScriptRoot 'fast-status.mjs'),$stateFile,$selected.Theme.id,[string]$readyTimeout,'--allow-hidden') -SeparateStderr
  Add-AriaLaunchTiming 'render-verification'
  if($check.ExitCode -ne 0){throw ('背景尚未切换成功：'+($check.ErrorOutput -join ' '))}
  if($ResultToken){Write-DreamSkinStartResult -StateRoot $stateRoot -Token $ResultToken -Outcome success -Category none -AppearanceRecovery not-needed}
  $completed=$true
 }else{
  $running=@()
  foreach($install in @(Get-DreamSkinRegisteredCodexInstalls)){$running+=@(Get-DreamSkinCodexProcesses -Codex $install)}
  if($running.Count -gt 0){throw '当前桌面端未连接换肤服务，已保留窗口。首次请退出后从 Aria 启动；连接后切换皮肤无需重启。'}
  # Start only when Codex is closed. Never pass restart or restart-confirmation switches.
  if(-not(Get-Command Move-DreamHubLegacyProfileWhenClosed -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'hub-data.ps1')}
  Move-DreamHubLegacyProfileWhenClosed -StateRoot $stateRoot
  & (Join-Path $PSScriptRoot 'start-dream-skin.ps1') -SavedThemeDirectory $SavedThemeDirectory -ResultToken $ResultToken
 }
}catch{
 if($snapshot){
  try{$null=Restore-DreamSkinActiveThemeSnapshot -SnapshotDirectory $snapshot -StateRoot $stateRoot -ExpectedContentFingerprint $before}catch{Write-Warning ('恢复原背景失败：'+$_.Exception.Message)}
 }
 if($wasPaused){$null=Set-DreamSkinPaused -Paused $true -StateRoot $stateRoot}
 if($ResultToken){Write-DreamSkinStartResult -StateRoot $stateRoot -Token $ResultToken -Outcome failure -Category renderer-verification-failed -AppearanceRecovery not-needed}
 throw
}finally{
 if($snapshot -and (Test-Path -LiteralPath $snapshot)){Remove-DreamSkinManagedDirectoryVerified -Path $snapshot -Root $stateRoot}
 if($lock){Exit-DreamSkinOperationLock -Mutex $lock}
 try{Write-DreamSkinUtf8FileAtomically -Path (Join-Path $stateRoot 'launcher-profile.json') -Content (([pscustomobject]@{at=[DateTime]::Now.ToString('o');hot=$completed;totalMs=$watch.ElapsedMilliseconds;steps=@($profileSteps)}|ConvertTo-Json -Depth 4)+[Environment]::NewLine)}catch{}
 ('{0:o} elapsed={1:F2}s quick={2}' -f (Get-Date),$watch.Elapsed.TotalSeconds,$completed)|Add-Content -LiteralPath (Join-Path $stateRoot 'launcher-timing.log') -Encoding UTF8
}
