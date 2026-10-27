param(
 [Parameter(Mandatory=$true)][string]$EngineRoot,
 [Parameter(Mandatory=$true)][string]$NodeExe,
 [string]$PlaywrightModule=$env:ARIA_PLAYWRIGHT_MODULE
)
$ErrorActionPreference='Stop'
$base=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.aria-snapshot-tests'))
$fixture=Join-Path $base ([guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'app'
$engine=Join-Path $root 'engine'
$codeRoot=Join-Path $engine 'scripts'
$requests=Join-Path $root 'user-backgrounds\requests'
$worker=$null;$browser=$null;$checks=0
function Assert-Test([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAIL: '+$Name)};$script:checks++}
function Wait-File([string]$Path,[int]$TimeoutMs=20000){$watch=[Diagnostics.Stopwatch]::StartNew();while(-not [IO.File]::Exists($Path)){if($watch.ElapsedMilliseconds -gt $TimeoutMs){throw ('Timed out waiting for '+[IO.Path]::GetFileName($Path))};Start-Sleep -Milliseconds 40}}
function Write-Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 20 -Compress),(New-Object Text.UTF8Encoding($false)))}
try{
 [void][IO.Directory]::CreateDirectory($engine)
 Copy-Item -LiteralPath (Join-Path $EngineRoot 'scripts') -Destination $engine -Recurse
 Copy-Item -LiteralPath (Join-Path $EngineRoot 'hub') -Destination $engine -Recurse
 # Rewrite paths in the throwaway fixture only, never the source installation.
 $sourceData=[IO.File]::ReadAllText((Join-Path $EngineRoot 'scripts\hub-data.ps1'))
 $found=[regex]::Match($sourceData,'\$script:DreamHubHome=''([^'']+)\\user-backgrounds''')
 if(-not $found.Success){throw 'Could not identify source installation root'}
 $sourceRoot=$found.Groups[1].Value
 foreach($file in Get-ChildItem -LiteralPath $codeRoot -Filter '*.ps1'){
  $source=[IO.File]::ReadAllText($file.FullName)
  $source=$source.Replace($sourceRoot,$root)
  # Isolate the import mutex from the real running application.
  $source=$source.Replace('"Local\Aria.$sid.ThemeImport"','"Local\AriaSnapshotTest.'+[IO.Path]::GetFileName($fixture)+'.$sid.ThemeImport"')
  $source=$source.Replace('"Local\CodexDreamSkin.$sid.ThemeImport"','"Local\AriaSnapshotTest.'+[IO.Path]::GetFileName($fixture)+'.$sid.ThemeImport"')
  [IO.File]::WriteAllText($file.FullName,$source,(New-Object Text.UTF8Encoding($true)))
 }
 foreach($part in @('runtime\themes','runtime\active-theme','user-backgrounds\themes','user-backgrounds\privacy','user-backgrounds\requests','user-backgrounds\thumbnails','user-backgrounds\scene-jobs\jobs')){[void][IO.Directory]::CreateDirectory((Join-Path $root $part))}
 # Simulate a slow snapshot inside the isolated copy and leave an external
 # signal for the browser test. The production implementation is unchanged.
 $dataPath=Join-Path $codeRoot 'hub-data.ps1'
 $dataSource=[IO.File]::ReadAllText($dataPath)
 $marker='function Get-DreamHubData {'
 if(-not $dataSource.Contains($marker)){throw 'Snapshot fixture hook could not be installed'}
 $pausePath=Join-Path $fixture 'pause.flag';$signal=Join-Path $fixture 'timing'
 $hook="`n if(Test-Path -LiteralPath '$pausePath'){[IO.File]::WriteAllText('$signal.worker-started','started');Start-Sleep -Seconds 8;[IO.File]::WriteAllText('$signal.worker-finished','finished')}"
 $dataSource=$dataSource.Replace($marker,$marker+$hook)
 [IO.File]::WriteAllText($dataPath,$dataSource,(New-Object Text.UTF8Encoding($true)))
 . (Join-Path $codeRoot 'common-windows.ps1')
 . (Join-Path $codeRoot 'theme-windows.ps1')
 . (Join-Path $codeRoot 'hub-privacy.ps1')
 . (Join-Path $codeRoot 'hub-snapshot-ui.ps1')
 $script:AriaPrivacyRoot=Join-Path $root 'user-backgrounds\privacy'
 $image=[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL7vAAAAABJRU5ErkJggg==')
 foreach($item in @(@{id='public-fixture';name='Public fixture'},@{id='secret-fixture';name='Private fixture'})){
  $dir=Join-Path $root ('user-backgrounds\themes\'+$item.id);[void][IO.Directory]::CreateDirectory($dir)
  [IO.File]::WriteAllBytes((Join-Path $dir 'art.png'),$image)
  Write-Json (Join-Path $dir 'theme.json') @{schemaVersion=1;id=$item.id;name=$item.name;image='art.png';appearance='auto'}
 }
 Write-Json (Join-Path $root 'runtime\active-theme\theme.json') @{id='public-fixture'}
 Write-Json (Join-Path $root 'runtime\theme-preferences.json') @{schemaVersion=1;themes=@{'public-fixture'=@{transparency='invalid';displayMode='native'}}}
 Write-Json (Join-Path $root 'user-backgrounds\favorites.json') @('public-fixture','secret-fixture')
 foreach($themeId in @('public-fixture','secret-fixture')){
  $jobId=[guid]::NewGuid().ToString('N')
  Write-Json (Join-Path $root ('user-backgrounds\scene-jobs\jobs\'+$jobId+'.json')) @{schemaVersion=1;id=$jobId;status='completed';name=('Notice for '+$themeId);themeId=$themeId;testOnly=$false;createdAt=[DateTime]::UtcNow.ToString('o')}
 }
 Write-AriaPrivacyConfig ([pscustomobject]@{schemaVersion=1;hiddenIds=@('secret-fixture');questions=@();password=@{}})
 $grant=New-AriaGrant 'hidden'
 $token=[guid]::NewGuid().ToString('N')
 $owner=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
 $workerArgs=@('-NoProfile','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $codeRoot 'hub-actions.ps1'),'-Worker','-WorkerType','snapshot','-OwnerPid',[string]$PID,'-OwnerStarted',$owner,'-QueueToken',$token)
 $worker=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $workerArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $fixture 'worker.out') -RedirectStandardError (Join-Path $fixture 'worker.err')
 function Snapshot([string]$Grant){
  $id=[guid]::NewGuid().ToString('N');$prefix=Join-Path $requests ($id+'.'+$token+'.snapshot')
  $protected=if($Grant){[AriaPrivacyCrypto]::Protect($Grant)}else{''}
  Write-Json ($prefix+'.request.json') @{id=1;action='snapshot';ariaHiddenAccess='';ariaHiddenProtected=$protected}
  Wait-File ($prefix+'.result.json')
  $raw=[IO.File]::ReadAllText($prefix+'.result.json');$result=$raw|ConvertFrom-Json
  if(-not $result.ok){throw ('Snapshot failed: '+$result.error+' '+$result.details)}
  Assert-Test ([bool]$result.ok -and [bool]$result.protectedSnapshot) 'encrypted snapshot response'
  Assert-Test (-not $raw.Contains('Private fixture') -and -not $raw.Contains('secret-fixture')) 'private theme absent from plaintext'
  $script:lastResult=$result
  return ([AriaPrivacyCrypto]::Unprotect([string]$result.protectedSnapshot)|ConvertFrom-Json)
 }
 $locked=Snapshot ''
 Assert-Test (-not $locked.data.hiddenUnlocked -and @($locked.data.hiddenThemes).Count -eq 0) 'locked snapshot omits private list'
 Assert-Test (@($locked.data.themes.id) -contains 'public-fixture' -and @($locked.data.themes.id) -notcontains 'secret-fixture') 'locked public list'
 Assert-Test (@($locked.data.favorites) -notcontains 'secret-fixture') 'locked favorites omit private theme'
 Assert-Test (@($locked.completedJobs.themeId) -notcontains 'secret-fixture' -and @($locked.completedJobs.themeId) -contains 'public-fixture') 'completion notices omit hidden theme'
 $fixtureTheme=@($locked.data.themes|Where-Object id -eq 'public-fixture')[0]
 Assert-Test ($null -eq $fixtureTheme.opacity -and $fixtureTheme.displayMode -eq 'native') 'invalid opacity does not hide theme or discard display mode'
 Write-Json (Join-Path $root 'runtime\theme-preferences.json') @{schemaVersion=1;themes=@{'public-fixture'=@{transparency=65;displayMode='contain'}}}
 $preferences=Snapshot ''
 $fixtureTheme=@($preferences.data.themes|Where-Object id -eq 'public-fixture')[0]
 Assert-Test ($fixtureTheme.opacity -eq 35 -and $fixtureTheme.displayMode -eq 'contain') 'changed preferences refresh without restarting worker'
 $unlocked=Snapshot $grant
 Assert-Test ([bool]$unlocked.data.hiddenUnlocked -and @($unlocked.data.hiddenThemes.id) -contains 'secret-fixture') 'authorized hidden snapshot'
 $unlockedResult=$script:lastResult
 $script:AriaHiddenToken=$grant;$script:HubGeneration=10;$script:LastData='';$script:TestMode=$false;$script:Published=@()
 function Send-HubMessage {param($Message) $script:Published+=@($Message)}
 function Update-AriaJobNotices {param($Jobs,$HiddenIds,$PublicIds)}
 $pending=[pscustomobject]@{SnapshotToken=$grant;Generation=10}
 Publish-AriaSnapshot -Result $unlockedResult -Pending $pending
 Assert-Test (@($script:Published|Where-Object {$_.type -eq 'state' -and $_.data.hiddenUnlocked}).Count -eq 1) 'authorized response published'
 $script:Published=@();$script:NextData=[DateTime]::MaxValue
 Publish-AriaSnapshot -Result $unlockedResult -Pending ([pscustomobject]@{SnapshotToken=$grant;Generation=9})
 Assert-Test ($script:Published.Count -eq 0 -and $script:NextData -eq [DateTime]::MinValue) 'stale generation discarded and retried'
 $script:AriaHiddenToken='replacement-grant';$script:Published=@()
 Publish-AriaSnapshot -Result $unlockedResult -Pending $pending
 Assert-Test ($script:Published.Count -eq 0 -and $script:AriaHiddenToken -eq 'replacement-grant') 'old response does not lock a newer grant'
 $script:AriaHiddenToken=$grant
 Assert-Test (Test-AriaSnapshotAuthorization -RequestedToken $grant -CurrentToken $grant -GrantValid $true) 'same active grant accepted'
 Assert-Test (-not(Test-AriaSnapshotAuthorization -RequestedToken $grant -CurrentToken $grant -GrantValid $false)) 'expired grant rejected'
 Assert-Test (-not(Test-AriaSnapshotAuthorization -RequestedToken $grant -CurrentToken 'new-grant' -GrantValid $true)) 'replaced grant rejected'
 Assert-Test (Test-AriaSnapshotAuthorization -RequestedToken '' -CurrentToken '' -GrantValid $false) 'normal locked state accepted'
 Assert-Test (-not(Test-AriaSnapshotAuthorization -RequestedToken '' -CurrentToken $grant -GrantValid $true)) 'old locked state rejected after unlock'
 Remove-AriaGrant $grant
 Assert-Test (-not(Test-AriaGrant -Token $grant -Role hidden)) 'grant revocation observed'
 Assert-Test (-not(Test-AriaSnapshotAuthorization -RequestedToken $grant -CurrentToken $grant -GrantValid (Test-AriaGrant -Token $grant -Role hidden))) 'delayed response rejected after revocation'
 $script:Published=@();$script:NextData=[DateTime]::MaxValue
 Publish-AriaSnapshot -Result $unlockedResult -Pending $pending
 Assert-Test (@($script:Published|Where-Object {$_.type -eq 'state' -and $_.data.hiddenUnlocked}).Count -eq 0) 'revoked response never published'
 Assert-Test (-not $script:AriaHiddenToken) 'expired grant cleared before retry'
 Assert-Test (@($script:Published|Where-Object {$_.type -eq 'privacyLocked'}).Count -eq 1) 'expired private view locked'
 Assert-Test ($null -eq $script:HubLatestData -and -not $script:LastData) 'expired private snapshot removed from UI cache'
 Assert-Test ($script:NextData -eq [DateTime]::MinValue) 'fresh locked snapshot requested'
 $revoked=Snapshot $grant
 Assert-Test (-not $revoked.data.hiddenUnlocked -and @($revoked.data.hiddenThemes).Count -eq 0) 'worker rejects revoked grant'
 Assert-Test (-not $worker.HasExited) 'worker survives sequential requests'
 if(-not $PlaywrightModule){throw 'Set ARIA_PLAYWRIGHT_MODULE to a Playwright installation to run responsiveness coverage'}
 $env:ARIA_PLAYWRIGHT_MODULE=$PlaywrightModule
 $browser=Start-Process -FilePath $NodeExe -ArgumentList @((Join-Path $PSScriptRoot 'aria-snapshot-responsiveness-test.mjs'),(Join-Path $engine 'hub'),$signal) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $fixture 'browser.out') -RedirectStandardError (Join-Path $fixture 'browser.err')
 Wait-File ($signal+'.ready')
 [IO.File]::WriteAllText($pausePath,'1')
 $id=[guid]::NewGuid().ToString('N');$prefix=Join-Path $requests ($id+'.'+$token+'.snapshot')
 Write-Json ($prefix+'.request.json') @{id=2;action='snapshot';ariaHiddenAccess=''}
 Wait-File ($signal+'.worker-started')
 if(-not $browser.WaitForExit(20000)){throw 'Browser responsiveness test timed out'}
 if(-not [IO.File]::Exists($signal+'.browser-ok')){throw ('Browser test failed: '+[IO.File]::ReadAllText((Join-Path $fixture 'browser.err'))+' '+[IO.File]::ReadAllText((Join-Path $fixture 'browser.out')))}
 Wait-File ($prefix+'.result.json') 20000
 Assert-Test (-not $worker.HasExited) 'worker remains usable after slow request'
 [IO.File]::Delete($pausePath)
 $again=Snapshot ''
 Assert-Test (@($again.data.themes.id) -contains 'public-fixture') 'worker handles subsequent request'
 Write-Output ('Snapshot checks passed: '+$checks+'; delayed worker and browser navigation verified.')
}finally{
 if($browser -and -not $browser.HasExited){$browser.Kill();$browser.WaitForExit()}
 if($worker -and -not $worker.HasExited){$worker.Kill();$worker.WaitForExit()}
 $resolved=[IO.Path]::GetFullPath($fixture);$prefix=$base.TrimEnd('\')+'\'
 if($resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
