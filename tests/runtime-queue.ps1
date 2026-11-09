param([string]$EngineRoot=(Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('.runtime-queue-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$script:checks=0
function Assert-Test([bool]$Value,[string]$Name){if(-not $Value){throw ('FAIL: '+$Name)};$script:checks++}
function Assert-Throws([scriptblock]$Action,[string]$Name){$threw=$false;try{& $Action}catch{$threw=$true};Assert-Test $threw $Name}
function Import-Functions([string]$Name){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $EngineRoot ('scripts\'+$Name)),[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ('Parse error in '+$Name)}
  foreach($fn in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    $code=$fn.Extent.Text.Replace('"Local\Aria.$sid.Scene.$Name"','"Local\AriaQueueTest.'+[IO.Path]::GetFileName($fixture)+'.$sid.Scene.$Name"')
    . ([scriptblock]::Create($code.Replace('function '+$fn.Name+' ','function script:'+$fn.Name+' ')))
  }
}
function Assert-DreamSkinNoReparseComponents {param([string]$Path) if(-not [IO.Path]::GetFullPath($Path).StartsWith($fixture+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture boundary'}}
function Test-DreamSkinPathWithin {param([string]$Path,[string]$Root) return [IO.Path]::GetFullPath($Path).StartsWith([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)}
function Write-DreamSkinUtf8FileAtomically {param([string]$Path,[string]$Content) Assert-DreamSkinNoReparseComponents $Path;[IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))}
function Get-DreamHubThemeById {param([string]$Id) if($Id -eq 'private-theme'){throw 'Locked'};return @{id=$Id}}
try{
  Import-Functions 'scene-queue.ps1';Import-Functions 'hub-workshop.ps1'
  . (Join-Path $EngineRoot 'scripts\hub-runtime-health.ps1')
  function Start-DreamSceneWorker {$script:starts++}
  $script:starts=0;$script:DreamSceneQueueRoot=Join-Path $fixture 'queue';Initialize-DreamSceneQueue
  $jobs=@();foreach($i in 1..3){$job=[pscustomobject]@{schemaVersion=1;id=([guid]::NewGuid().ToString('N'));name=('Fixture '+$i);status='queued';themeId='';createdAt=[DateTime]::UtcNow.AddMinutes($i).ToString('o');updatedAt='';workerPid=0;workerStartedAt='';message='';error=''};Save-DreamSceneJob $job;$jobs+=,$job}
  Assert-Test ((Get-AriaNextQueuedJob (Get-DreamSceneJobs)).id -ceq $jobs[0].id) 'FIFO remains default'
  $before=(Get-FileHash -LiteralPath (Get-DreamSceneJobPath $jobs[2].id)).Hash
  $null=Set-AriaQueuePriority $jobs[2].id
  Assert-Test ((Get-AriaNextQueuedJob (Get-DreamSceneJobs)).id -ceq $jobs[2].id) 'prioritized queued item is next'
  Assert-Test ((Get-FileHash -LiteralPath (Get-DreamSceneJobPath $jobs[2].id)).Hash -ceq $before) 'priority preserves worker status file'
  $jobs[0].status='recording';Save-DreamSceneJob $jobs[0];$activeHash=(Get-FileHash -LiteralPath (Get-DreamSceneJobPath $jobs[0].id)).Hash
  Assert-Throws {Set-AriaQueuePriority $jobs[0].id} 'active recording cannot be reprioritized'
  $null=Set-AriaQueuePaused $true
  Assert-Test ($null -eq (Get-AriaNextQueuedJob (Get-DreamSceneJobs))) 'pause prevents next task'
  Assert-Test ((Get-AriaQueueSettings).paused) 'pause persists on disk'
  Assert-Test ((Get-FileHash -LiteralPath (Get-DreamSceneJobPath $jobs[0].id)).Hash -ceq $activeHash) 'pause preserves current recording'
  $null=Set-AriaQueuePaused $false
  Assert-Test ($script:starts -eq 1 -and (Get-AriaNextQueuedJob (Get-DreamSceneJobs)).id -ceq $jobs[2].id) 'resume starts worker with preserved priority'
  [IO.File]::WriteAllText((Get-DreamSceneJobPath $jobs[2].id 'cancel'),'cancel')
  Assert-Test ((Get-AriaNextQueuedJob (Get-DreamSceneJobs)).id -ceq $jobs[1].id) 'cancellation marker excludes queued item'
  Assert-Throws {Set-AriaQueuePriority $jobs[2].id} 'cancelled item cannot be prioritized'
  $jobs[1].themeId='private-theme';Save-DreamSceneJob $jobs[1]
  Assert-Throws {Set-AriaQueuePriority $jobs[1].id} 'hidden theme authorization is enforced'
  Assert-Throws {Set-AriaQueuePriority '../bad'} 'invalid identifiers are rejected'
  [IO.File]::WriteAllText((Join-Path $script:DreamSceneQueueRoot 'queue-control.json'),'broken')
  Assert-Test ((Get-AriaQueueSettings).paused) 'damaged pause state fails closed'
  Assert-Throws {Set-AriaQueuePaused $false} 'damaged control file is preserved'

  $workshop=Join-Path $fixture 'workshop';$content=Join-Path $workshop 'content\431960';[void][IO.Directory]::CreateDirectory($content)
  $manifest=Join-Path $workshop 'appworkshop_431960.acf'
  [IO.File]::WriteAllText($manifest,'"WorkshopItemsInstalled" { "12345678" { "manifest" "1" } } "WorkshopItemDetails" { "12345678" { "latest_manifest" "1" } }')
  $one=Get-AriaWorkshopManifest $manifest;$two=Get-AriaWorkshopManifest $manifest
  Assert-Test ([object]::ReferenceEquals($one,$two)) 'unchanged manifest reuses parsed content'
  Assert-Test (Test-DreamHubWorkshopReady $content '12345678') 'matching installed manifest is ready'
  [IO.File]::WriteAllText($manifest,'"WorkshopItemsInstalled" { "12345678" { "manifest" "1" } } "WorkshopItemDetails" { "12345678" { "latest_manifest" "222" } }')
  Assert-Test (-not(Test-DreamHubWorkshopReady $content '12345678')) 'manifest change invalidates cache immediately'

  $script:HubRequests=Join-Path $fixture 'requests';[void][IO.Directory]::CreateDirectory($script:HubRequests)
  $worker=[pscustomobject]@{HasExited=$false;Killed=$false;Disposed=$false}
  $worker|Add-Member ScriptMethod Kill {$this.Killed=$true;$this.HasExited=$true}
  $worker|Add-Member ScriptMethod WaitForExit {param($milliseconds)return $this.HasExited}
  $worker|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
  $script:AriaSnapshotWorker=$worker
  $prefix=Join-Path $script:HubRequests ([guid]::NewGuid().ToString('N'))
  $pending=[pscustomobject]@{Action='snapshot';Persistent=$true;Process=$worker;Started=[DateTime]::UtcNow.AddSeconds(-31);InputPath=$prefix+'.request.json';Path=$prefix+'.result.json'}
  Assert-Test (Test-AriaStalledSnapshot $pending) 'stalled snapshot is detected'
  $pending.Action='launch';Assert-Test (-not(Test-AriaStalledSnapshot $pending)) 'launch tasks are outside snapshot deadline'
  $pending.Action='snapshot';$pending.Started=[DateTime]::UtcNow;Assert-Test (-not(Test-AriaStalledSnapshot $pending)) 'recent snapshot is retained'
  $pending.Started=[DateTime]::UtcNow.AddSeconds(-31)
  [IO.File]::WriteAllText($pending.Path,'{"ok":true,"protectedSnapshot":"fixture"}');Assert-Test (-not(Test-AriaStalledSnapshot $pending)) 'finished snapshot gets published before recovery'
  [IO.File]::WriteAllText($pending.Path,'{"ok":false,"error":"fixture failure"}');Assert-Test (-not(Test-AriaStalledSnapshot $pending)) 'valid failure response is handled normally'
  foreach($broken in @('{"ok":','null','')){[IO.File]::WriteAllText($pending.Path,$broken);Assert-Test (Test-AriaStalledSnapshot $pending) 'invalid response cannot block snapshot recovery'}
  [IO.File]::Delete($pending.Path)
  $pending.Process=[pscustomobject]@{HasExited=$false};Assert-Test (-not(Test-AriaStalledSnapshot $pending)) 'stale worker cannot terminate newer worker';$pending.Process=$worker
  [IO.File]::WriteAllText($pending.InputPath.Replace('.request.json','.processing.json'),'fixture')
  $script:HubPending=[Collections.Generic.List[object]]::new();$script:HubPending.Add($pending);$script:HubGeneration=4
  function Write-AriaSnapshotError {param($Message)};function Send-HubMessage {param($Message)$script:lastNotice=$Message}
  Assert-Test (Reset-AriaStalledSnapshot $pending) 'recovery finishes'
  Assert-Test ($worker.Killed -and $worker.Disposed -and $null -eq $script:AriaSnapshotWorker) 'only owned snapshot worker is retired'
  Assert-Test ($script:HubPending.Count -eq 0 -and $script:HubGeneration -eq 5) 'stale pending request removed and generation advanced'
  Assert-Test (-not[IO.File]::Exists($pending.InputPath.Replace('.request.json','.processing.json'))) 'claimed snapshot request cleaned'
  Assert-Test ($script:lastNotice.type -eq 'notice') 'recovery gives gentle feedback'
  $script:HubLatestData=[pscustomobject]@{themes=@([pscustomobject]@{id='fixture';thumbnail=''});hiddenThemes=@()};$script:LastThumbCheck=[DateTime]::UtcNow;$script:LastMissingThumbs=''
  Update-AriaThumbnailSchedule;Assert-Test ($script:LastThumbCheck -eq [DateTime]::MinValue) 'new missing cover prepares promptly'
  $script:LastThumbCheck=[DateTime]::UtcNow;$last=$script:LastThumbCheck;Update-AriaThumbnailSchedule
  Assert-Test ($script:LastThumbCheck -eq $last) 'unchanged missing covers wait for reconciliation'
  'PASS: '+$script:checks+' runtime and queue checks'
}finally{
  $full=[IO.Path]::GetFullPath($fixture);$testRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
  if($full.StartsWith($testRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('.runtime-queue-')){Remove-Item -LiteralPath $full -Recurse -Force}
}
