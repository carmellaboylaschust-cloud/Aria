param([string]$EngineRoot=(Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('.launch-worker-'+[guid]::NewGuid().ToString('N'))
$requests=Join-Path $fixture 'requests'
[void][IO.Directory]::CreateDirectory($requests)
$worker=$null

try {
  Copy-Item -LiteralPath (Join-Path $EngineRoot 'scripts\hub-actions.ps1') -Destination $fixture
  $launcher=Get-Content -LiteralPath (Join-Path $EngineRoot 'scripts\apply-or-start.ps1') -Raw -Encoding UTF8
  if(-not $launcher.Contains("'D:\Aria\runtime'")){throw 'Cannot isolate the launcher runtime path.'}
  $launcher=$launcher.Replace("'D:\Aria\runtime'",("'"+$fixture.Replace("'","''")+"'"))
  [IO.File]::WriteAllText((Join-Path $fixture 'apply-or-start.ps1'),$launcher,[Text.UTF8Encoding]::new($true))
  foreach($name in @('theme-windows','background-library','scene-queue','hub-workshop','hub-feed')){
    Set-Content -LiteralPath (Join-Path $fixture ($name+'.ps1')) -Value ''
  }
  Set-Content -LiteralPath (Join-Path $fixture 'hub-data.ps1') -Encoding UTF8 -Value @'
$script:DreamHubHome=$PSScriptRoot
$script:DreamHubState=$PSScriptRoot
function Get-DreamHubThemeById($Id) { @{Directory=$Id} }
function Get-AriaCurrentSkinSnapshot { $null }
function Save-AriaPreviousSkin($Previous,$AppliedId) { }
function Set-AriaLibraryMeta($Ids,[switch]$RecordUse) { }
'@
  Set-Content -LiteralPath (Join-Path $fixture 'common-windows.ps1') -Encoding UTF8 -Value @'
function Test-DreamSkinPathWithin($Path,$Root) {
  [IO.Path]::GetFullPath($Path).StartsWith([IO.Path]::GetFullPath($Root)+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Assert-DreamSkinNoReparseComponents($Path) { }
function Read-DreamHubJson($Path,$Default) {
  if([IO.File]::Exists($Path)){return [IO.File]::ReadAllText($Path)|ConvertFrom-Json}
  return $Default
}
function Write-DreamHubJson($Path,$Data) {
  $temporary=$Path+'.tmp'
  [IO.File]::WriteAllText($temporary,($Data|ConvertTo-Json -Compress))
  if([IO.File]::Exists($Path)){
    $backup=$Path+'.old'
    [IO.File]::Replace($temporary,$Path,$backup)
    [IO.File]::Delete($backup)
  }else{
    [IO.File]::Move($temporary,$Path)
  }
}
function Read-DreamSkinState($Path) { $null }
function Get-DreamSkinNodeRuntime { @{Path='fixture'} }
function Get-DreamSkinRegisteredCodexInstalls { }
function Get-DreamSkinCodexInstallFromState($State) { $null }
function Get-DreamSkinLocalOpacity($ThemeId,$StateRoot) { $null }
function Get-DreamSkinDisplayMode($ThemeId,$StateRoot) { 'cover' }
function Get-DreamSkinStartResultPath($StateRoot,$Token) { Join-Path $StateRoot ('.start-result-'+$Token+'.json') }
function Read-DreamSkinStartResult($StateRoot,$Token) {
  Read-DreamHubJson (Get-DreamSkinStartResultPath $StateRoot $Token) $null
}
function Write-DreamSkinStartResult($StateRoot,$Token,$Outcome,$Category,$AppearanceRecovery) {
  Write-DreamHubJson (Get-DreamSkinStartResultPath $StateRoot $Token) @{
    token=$Token;outcome=$Outcome;category=$Category;appearanceRecovery=$AppearanceRecovery
  }
}
function Move-DreamHubLegacyProfileWhenClosed($StateRoot) { }
'@
  Set-Content -LiteralPath (Join-Path $fixture 'start-dream-skin.ps1') -Encoding UTF8 -Value @'
param($SavedThemeDirectory,$ResultToken)
if($SavedThemeDirectory -eq 'slow-fixture'){throw 'Fixture renderer status timeout'}
Write-DreamSkinStartResult -StateRoot $PSScriptRoot -Token $ResultToken -Outcome success -Category none -AppearanceRecovery not-needed
'@

  $workerPath=Join-Path $fixture 'hub-actions.ps1'
  $queueToken=[guid]::NewGuid().ToString('N')
  $ownerStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
  $stderr=Join-Path $fixture 'worker-error.log'
  $worker=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
    '-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',('"'+$workerPath+'"'),
    '-Worker','-OwnerPid',"$PID",'-OwnerStarted',$ownerStarted,'-QueueToken',$queueToken
  ) -RedirectStandardError $stderr -WindowStyle Hidden -PassThru

  $requestId=0
  foreach($theme in @('slow-fixture','working-fixture')){
    $requestId++
    $entry=[guid]::NewGuid().ToString('N')+'.'+$queueToken+'.launch'
    $request=Join-Path $requests ($entry+'.request.json')
    $response=Join-Path $requests ($entry+'.result.json')
    [IO.File]::WriteAllText($request+'.tmp',(@{id=$requestId;action='launch';themeId=$theme}|ConvertTo-Json -Compress))
    [IO.File]::Move($request+'.tmp',$request)
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(-not [IO.File]::Exists($response)){
      if($worker.HasExited){throw ('Worker exited: '+[IO.File]::ReadAllText($stderr))}
      if($wait.Elapsed.TotalSeconds -gt 12){
        $requestState=if([IO.File]::Exists($request)){'unclaimed'}elseif([IO.File]::Exists((Join-Path $requests ($entry+'.processing.json')))){'processing'}else{'consumed'}
        throw "Missing worker response for request $requestId ($requestState)."
      }
      Start-Sleep -Milliseconds 50
    }
    $result=[IO.File]::ReadAllText($response)|ConvertFrom-Json
    $expectedSuccess=$requestId -eq 2
    if($result.id -ne $requestId -or $result.ok -isnot [bool] -or $result.ok -ne $expectedSuccess){
      throw "Wrong worker response for request $requestId."
    }
    if(-not $expectedSuccess -and $result.error -cne 'Fixture renderer status timeout'){
      throw 'The original renderer error was lost.'
    }
    $launchResults=@(Get-ChildItem -LiteralPath $fixture -Filter '.start-result-*.json' -File | ForEach-Object {
      [IO.File]::ReadAllText($_.FullName)|ConvertFrom-Json
    })
    if($launchResults.Count -ne $requestId -or @($launchResults|Where-Object outcome -eq 'failure').Count -ne 1 -or
        @($launchResults|Where-Object outcome -eq 'success').Count -ne ($requestId-1)){
      throw 'The launcher structured result was corrupted or missing.'
    }
  }
  if($worker.HasExited){throw 'The worker stopped instead of taking another request.'}
  'Warm worker published a failure and the next success through their two IPC paths while preserving both launcher results.'
} finally {
  if($worker){
    if(-not $worker.HasExited){Stop-Process -InputObject $worker;[void]$worker.WaitForExit(5000)}
    $worker.Dispose()
  }
  $root=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
  $full=[IO.Path]::GetFullPath($fixture)
  if($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and
      [IO.Path]::GetFileName($full) -match '^\.launch-worker-[a-f0-9]{32}$'){
    Remove-Item -LiteralPath $full -Recurse -Force
  }
}
