param([string]$EngineRoot=(Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference='Stop'
$source=Join-Path $EngineRoot 'scripts\skin-hub.ps1'
$tokens=$null
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $source).Path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}

# Load the host queue functions and its actual timer loop without starting a WinForms/WebView window.
foreach($name in @('Start-HubAction','Test-AriaMissingLaunchResult')){
    $functionAst=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if(-not $functionAst){throw "Missing host function $name"}
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
$pollLoop=$ast.Find({param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and
        $node.Variable.VariablePath.UserPath -eq 'pending' -and $node.Condition.Extent.Text -match 'HubPending\.ToArray\('
},$true)
if(-not $pollLoop){throw 'Cannot locate the host pending-action timer.'}
$poll=[scriptblock]::Create($pollLoop.Extent.Text)

$script:HubRequests=Join-Path $PSScriptRoot ('.launch-host-'+[guid]::NewGuid().ToString('N'))
$script:HubPending=[Collections.Generic.List[object]]::new()
$script:LaunchInFlight=$false
$script:AriaLaunchQueueToken='fixture'
$script:HubGeneration=0
$messages=[Collections.Generic.List[object]]::new()
function Get-AriaLaunchWorker { [pscustomobject]@{HasExited=$false} }
function Reset-AriaStalledSnapshot { $false }
function Send-HubMessage($Message) { $messages.Add($Message) }
function Write-DreamHubJson($Path,$Value) { [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Compress)) }
function Read-DreamHubJson($Path,$Default) { try {[IO.File]::ReadAllText($Path)|ConvertFrom-Json} catch {return $Default} }
function New-FixtureRequest([int]$Id) { [pscustomobject]@{id=$Id;action='launch';themeId="fixture-$Id"} }
function Assert-Settled([int]$MessagesExpected) {
    if($script:LaunchInFlight -or $script:HubPending.Count -or $messages.Count -ne $MessagesExpected -or $messages[$MessagesExpected-1].type -ne 'launchDone'){
        throw 'The host did not release the UI exactly once after the request ended.'
    }
}

try {
    # The queue directory does not exist yet. Publication must fail before acquiring the busy flag.
    $failed=$false
    try {Start-HubAction (New-FixtureRequest 1)} catch {$failed=$true}
    if(-not $failed -or $script:LaunchInFlight -or $script:HubPending.Count){throw 'An enqueue failure locked the host.'}

    [void][IO.Directory]::CreateDirectory($script:HubRequests)
    Start-HubAction (New-FixtureRequest 2)
    $entry=$script:HubPending[0]
    if(-not $script:LaunchInFlight -or (Test-AriaMissingLaunchResult $entry)){throw 'An unclaimed request must remain pending.'}
    & $poll
    $rejected=$false
    try {Start-HubAction (New-FixtureRequest 3)} catch {$rejected=$true}
    if(-not $rejected -or $script:HubPending.Count -ne 1){throw 'Concurrent launches entered the same queue.'}
    $claim=$entry.InputPath.Replace('.request.json','.processing.json')
    [IO.File]::Move($entry.InputPath,$claim)
    & $poll
    if((Test-AriaMissingLaunchResult $entry) -or -not $script:LaunchInFlight -or $messages.Count){throw 'An active claim was released prematurely.'}

    [IO.File]::Delete($claim)
    if(-not(Test-AriaMissingLaunchResult $entry)){throw 'The host did not detect a lost reply.'}
    & $poll
    Assert-Settled 1

    Start-HubAction (New-FixtureRequest 4)
    $entry=$script:HubPending[0]
    Write-DreamHubJson $entry.Path @{id=4;ok=$true;message='fixture-success'}
    [IO.File]::Delete($entry.InputPath)
    if(Test-AriaMissingLaunchResult $entry){throw 'A published reply was reported missing.'}
    & $poll
    Assert-Settled 2
    if($messages[1].message -ne 'fixture-success'){throw 'The successful follow-up reply was lost.'}

    foreach($invalid in @('{','{"ok":true,"id":99,"message":"wrong-request"}')){
        Start-HubAction (New-FixtureRequest 5)
        $entry=$script:HubPending[0]
        [IO.File]::WriteAllText($entry.Path,$invalid)
        [IO.File]::Delete($entry.InputPath)
        $expected=$messages.Count+1
        & $poll
        Assert-Settled $expected
        if(-not $messages[$expected-1].message -or $messages[$expected-1].message -eq 'wrong-request'){throw 'The invalid reply was accepted.'}
    }
    'PASS: failed enqueue, active request and claim, missing or invalid completion, and successful follow-up.'
} finally {
    $parent=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($script:HubRequests)
    if([IO.Path]::GetDirectoryName($full) -eq $parent -and [IO.Path]::GetFileName($full) -match '^\.launch-host-[a-f0-9]{32}$' -and [IO.Directory]::Exists($full)){
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
