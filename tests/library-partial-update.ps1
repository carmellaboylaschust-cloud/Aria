param([string]$EngineRoot=(Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference='Stop'
. (Join-Path $EngineRoot 'scripts\hub-library.ps1')
$script:DreamHubHome=$PSScriptRoot
$script:fixture=[pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{one=[pscustomobject]@{group='A';tags=@('one-tag')};two=[pscustomobject]@{group='B';tags=@('two-tag')}}}
function Get-DreamHubThemeById {param($Id) if($Id -notin @('one','two')){throw 'Unknown fixture'};return $Id}
function Enter-DreamSceneMutex {param($Name) return $true}
function Exit-DreamSceneMutex {param($Guard)}
function Read-DreamHubJson {param($Path,$Default) return $script:fixture}
function Write-DreamHubJson {param($Path,$Value) $script:fixture=$Value}
function Assert-Equal {param($Actual,$Expected) if(($Actual|ConvertTo-Json -Compress) -cne ($Expected|ConvertTo-Json -Compress)){throw 'Assertion failed'}}
Set-AriaLibraryMeta -Ids @('one','two') -Group 'Together'
Assert-Equal $script:fixture.themes.one.tags @('one-tag');Assert-Equal $script:fixture.themes.two.tags @('two-tag')
Set-AriaLibraryMeta -Ids @('one','two') -Tags @('new-tag')
Assert-Equal $script:fixture.themes.one.group 'Together';Assert-Equal $script:fixture.themes.two.group 'Together'
Set-AriaLibraryMeta -Ids @('one','two') -Group ''
Assert-Equal $script:fixture.themes.one.group '';Assert-Equal $script:fixture.themes.one.tags @('new-tag')
Set-AriaLibraryMeta -Ids @('one','two') -Tags @()
Assert-Equal @($script:fixture.themes.one.tags).Count 0
Set-AriaLibraryMeta -Ids @('one') -Name 'Renamed'
Assert-Equal $script:fixture.themes.one.name 'Renamed';Assert-Equal @($script:fixture.themes.one.tags).Count 0
Write-Output 'Library partial-update checks passed: group-only, tags-only, clear, and rename.'
