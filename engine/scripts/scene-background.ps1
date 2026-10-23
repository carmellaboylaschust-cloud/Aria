
function Start-AriaSceneBackgroundWindow {
 param([ValidatePattern('^(?:AriaCapture|CodexScene)-[a-f0-9]{32}$')][string]$Title)
 if(-not('AriaSceneBackgroundGuard' -as [type])){
  Add-Type -Path (Join-Path (Split-Path $PSScriptRoot) 'assets\AriaSceneBackgroundGuard.cs')
 }
 return [AriaSceneBackgroundGuard]::new($Title,[IO.Path]::GetDirectoryName($script:DreamSceneEngine))
}
