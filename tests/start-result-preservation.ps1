param([string]$EngineRoot=(Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('.launch-result-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
  $source=Get-Content -LiteralPath (Join-Path $EngineRoot 'scripts\apply-or-start.ps1') -Raw -Encoding UTF8
  $source=$source.Replace('D:\Aria\runtime',$fixture)
  [IO.File]::WriteAllText((Join-Path $fixture 'apply-or-start.ps1'),$source,[Text.UTF8Encoding]::new($true))
  Set-Content -LiteralPath (Join-Path $fixture 'common-windows.ps1') -Encoding UTF8 -Value @'
function Read-DreamSkinState { $null }
function Get-DreamSkinNodeRuntime { @{Path='fixture'} }
function Get-DreamSkinRegisteredCodexInstalls { }
function Get-DreamSkinStartResultPath($StateRoot,$Token) { Join-Path $StateRoot ('.start-result-'+$Token+'.json') }
function Write-DreamSkinStartResult($StateRoot,$Token,$Outcome,$Category,$AppearanceRecovery) {
  $path=Get-DreamSkinStartResultPath $StateRoot $Token
  if(Test-Path -LiteralPath $path){throw 'Refusing second result write'}
  [IO.File]::WriteAllText($path,($Outcome+';'+$Category+';'+$AppearanceRecovery))
}
function Move-DreamHubLegacyProfileWhenClosed($StateRoot) { }
'@
  Set-Content -LiteralPath (Join-Path $fixture 'theme-windows.ps1') -Value ''
  Set-Content -LiteralPath (Join-Path $fixture 'start-dream-skin.ps1') -Value @'
param($SavedThemeDirectory,$ResultToken)
if($SavedThemeDirectory -eq 'child-reports'){
  Write-DreamSkinStartResult -StateRoot $PSScriptRoot -Token $ResultToken -Outcome failure -Category cdp-endpoint-unavailable -AppearanceRecovery restored
}
throw 'Original startup failure'
'@
  foreach($case in @(
    @{Name='child-reports';Expected='failure;cdp-endpoint-unavailable;restored'},
    @{Name='child-fails-before-reporting';Expected='failure;renderer-verification-failed;not-needed'}
  )){
    $token=[guid]::NewGuid().ToString('N')
    try { & (Join-Path $fixture 'apply-or-start.ps1') -SavedThemeDirectory $case.Name -ResultToken $token;throw 'Expected failure' }
    catch { if($_.Exception.Message -cne 'Original startup failure'){throw} }
    $stored=[IO.File]::ReadAllText((Join-Path $fixture ('.start-result-'+$token+'.json')))
    if($stored -cne $case.Expected){throw ('Wrong result for '+$case.Name)}
  }
  'Both launch failures retained their original error and a single structured result.'
} finally {
  $root=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
  $full=[IO.Path]::GetFullPath($fixture)
  if($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and
      [IO.Path]::GetFileName($full) -match '^\.launch-result-[a-f0-9]{32}$'){
    Remove-Item -LiteralPath $full -Recurse -Force
  }
}
