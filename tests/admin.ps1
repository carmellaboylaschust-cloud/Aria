param([string]$Root=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'engine\scripts\common-windows.ps1')
. (Join-Path $Root 'engine\scripts\theme-windows.ps1')
. (Join-Path $Root 'engine\scripts\hub-privacy.ps1')
. (Join-Path $Root 'engine\scripts\hub-privacy-extra.ps1')
$fixture=Join-Path $Root ('.test-output\privacy-'+[guid]::NewGuid().ToString('N'))
$script:AriaPrivacyRoot=$fixture
$password=[guid]::NewGuid().ToString('N')
$script:Checks=0
function Assert-Test([bool]$Value,[string]$Name){if(-not $Value){throw "FAIL: $Name"};$script:Checks++}
function Reject-Test([scriptblock]$Action,[string]$Name){$rejected=$false;try{& $Action}catch{$rejected=$true};Assert-Test $rejected $Name}
$questions=@([pscustomobject]@{question='Test question one?';answer='alpha'},[pscustomobject]@{question='Test question two?';answer='beta'})
Assert-Test (-not(Test-AriaPrivacyInitialized)) 'fresh install'
Reject-Test {Initialize-AriaPrivacy -Password 'short' -Confirmation 'short' -Questions $questions} 'short password'
Reject-Test {Initialize-AriaPrivacy -Password $password -Confirmation 'different' -Questions $questions} 'confirmation'
Reject-Test {Initialize-AriaPrivacy -Password $password -Confirmation $password -Questions @()} 'question required'
Initialize-AriaPrivacy -Password $password -Confirmation $password -Questions $questions
Assert-Test (Test-AriaPrivacyInitialized) 'initialized'
$old=(Get-FileHash (Join-Path $fixture 'vault.dat')).Hash
Reject-Test {Initialize-AriaPrivacy -Password $password -Confirmation $password -Questions $questions} 'overwrite blocked'
Assert-Test ((Get-FileHash (Join-Path $fixture 'vault.dat')).Hash -eq $old) 'vault preserved'
Reject-Test {Get-AriaQuestionBank} 'question bank authorization'
1..5|ForEach-Object {Reject-Test {Unlock-AriaAdmin 'wrong'} 'wrong password'}
Reject-Test {Unlock-AriaAdmin $password} 'cooldown'
$script:AriaPrivacyRetryAfter=[DateTime]::MinValue
Unlock-AriaAdmin $password
Assert-Test (Test-AriaGrant -Role admin) 'admin login'
Assert-Test (@(Get-AriaQuestionBank).Count -eq 2) 'question list'
Assert-Test (-not(Test-AriaGrant -Role hidden)) 'role separation'
$challenge=New-AriaPrivacyChallenge
$answer=if($challenge.question -eq 'Test question one?'){'alpha'}else{'beta'}
Unlock-AriaHidden $challenge.challengeId $answer
Assert-Test (Test-AriaGrant -Role hidden) 'answer unlock'
Reject-Test {Unlock-AriaHidden $challenge.challengeId $answer} 'challenge single use'
$next=[guid]::NewGuid().ToString('N')
Change-AriaAdminPassword -CurrentPassword $password -NewPassword $next -Confirmation $next
Assert-Test (-not(Test-AriaGrant -Role admin)) 'admin grant revoked'
Assert-Test (-not(Test-AriaGrant -Role hidden)) 'hidden grant revoked'
Reject-Test {Unlock-AriaAdmin $password} 'old password revoked'
Unlock-AriaAdmin $next
Assert-Test (Test-AriaGrant -Role admin) 'new password'
Lock-AriaAdmin
Assert-Test (-not(Test-AriaGrant -Role admin)) 'explicit lock'
$script:AriaPrivacyRoot=Join-Path $fixture 'legacy'
$salt=[AriaPrivacyCrypto]::Random()
$legacy=[guid]::NewGuid().ToString('N').Substring(0,6)
Write-AriaPrivacyConfig ([pscustomobject]@{schemaVersion=1;password=[pscustomobject]@{salt=$salt;hash=[AriaPrivacyCrypto]::Hash($legacy,$salt)};questions=@();hiddenIds=@('fixture-theme')})
Unlock-AriaAdmin $legacy
Assert-Test (Test-AriaGrant -Role admin) 'legacy password compatibility'
Assert-Test ((Get-AriaHiddenIds) -contains 'fixture-theme') 'hidden ids preserved'
Lock-AriaAdmin
Write-Output "Administrator security checks passed: $script:Checks"
$parseFailures=@()
Get-ChildItem -LiteralPath (Join-Path $Root 'engine\scripts') -Filter '*.ps1'|ForEach-Object {$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors);if($errors){$parseFailures+=@($_.Name)}}
Assert-Test ($parseFailures.Count -eq 0) ('PowerShell syntax: '+($parseFailures -join ','))
Write-Output 'PowerShell source syntax passed'
