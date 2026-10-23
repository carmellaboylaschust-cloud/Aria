param([Parameter(Mandatory=$true)][string]$EngineRoot)
$ErrorActionPreference='Stop'
. (Join-Path $EngineRoot 'scripts\common-windows.ps1')
. (Join-Path $EngineRoot 'scripts\theme-windows.ps1')
. (Join-Path $EngineRoot 'scripts\hub-policy.ps1')
. (Join-Path $EngineRoot 'scripts\hub-backup.ps1')
$fixture=Join-Path $env:TEMP ('aria-limits-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$script:DreamHubRoot=$fixture
$video=Join-Path $fixture 'synthetic.mp4'
[IO.File]::WriteAllText($video,'synthetic size-policy fixture')
$script:VideoLength=512MB
$script:SceneLength=1024MB
$script:Count=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$script:Count++}
function MustReject([scriptblock]$Action,[string]$Pattern){$caught=$false;try{& $Action}catch{if($_.Exception.Message -notmatch $Pattern){throw};$caught=$true};Check $caught 'Oversize content accepted'}
# Synthetic metadata keeps these boundary checks fast and independent of media libraries.
function Get-Item {param([string]$LiteralPath,[switch]$Force) [pscustomobject]@{Length=$script:VideoLength;Extension='.mp4';FullName=$LiteralPath}}
function Assert-DreamSkinNoReparseComponents {param([string]$Path)}
function Assert-DreamHubFreeSpace {}
function Invoke-DreamSkinNative {param($FilePath,$ArgumentList,[switch]$SeparateStderr) [pscustomobject]@{ExitCode=0;Output=@('{"streams":[{"codec_name":"h264","width":3840,"height":2160}]}')}}
function Get-DreamHubProjectFiles {param($ProjectPath) [pscustomobject]@{Length=$script:SceneLength}}
function Write-TestPolicy($VideoMB,$SceneMB){[IO.File]::WriteAllText((Join-Path $fixture 'import-policy.json'),(@{videoMaxMB=$VideoMB;sceneMaxMB=$SceneMB}|ConvertTo-Json))}
try{
 Write-TestPolicy 512 1024
 $policy=Get-DreamHubPolicy
 Check ($policy.videoMaxMB -eq 512 -and $policy.sceneMaxMB -eq 1024) 'New limits did not survive loading'
 Assert-DreamHubMediaPolicy $video;Check $true '512 MB import'
 Assert-DreamSkinImageFile $video -SkipImageMetadata;Check $true '512 MB theme validation'
 $script:VideoLength=512MB+1
 MustReject {Assert-DreamHubMediaPolicy $video} '512 MB'
 MustReject {Assert-DreamSkinImageFile $video -SkipImageMetadata} '512 MB'
 Assert-DreamHubScenePolicy 'synthetic-project';Check $true '1024 MB scene/web'
 $script:SceneLength=1024MB+1
 MustReject {Assert-DreamHubScenePolicy 'synthetic-project'} '1024 MB'
 Write-TestPolicy 256 512
 $script:VideoLength=256MB+1;$script:SceneLength=512MB+1
 MustReject {Assert-DreamHubMediaPolicy $video} '256 MB'
 MustReject {Assert-DreamHubScenePolicy 'synthetic-project'} '512 MB'
 Write-TestPolicy 9999 9999
 $policy=Get-DreamHubPolicy
 Check ($policy.videoMaxMB -eq 512 -and $policy.sceneMaxMB -eq 1024) 'Configured limits escaped maximum'
 # Exercise backup import validation using declared ZIP entry lengths.
 foreach($length in @(512MB,(512MB+1))){
  $manifest=[pscustomobject]@{format='aria-backup/1';scope='public';skinIds=@('fixture');totalBytes=($length+2);files=@(
   @{path='skins/fixture/theme.json';size=2;sha256=('a'*64)},
   @{path='skins/fixture/background.mp4';size=$length;sha256=('b'*64)}
  )}
  $entry=[pscustomobject]@{FullName='manifest.json';Bytes=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 8));Length=0}
  $entry.Length=$entry.Bytes.Length
  $entry|Add-Member ScriptMethod Open {return [IO.MemoryStream]::new($this.Bytes)}
  $archive=[pscustomobject]@{Entries=@($entry,[pscustomobject]@{FullName='skins/fixture/theme.json';Length=2},[pscustomobject]@{FullName='skins/fixture/background.mp4';Length=$length})}
  $archive|Add-Member ScriptMethod GetEntry {param($Name) return $this.Entries|Where-Object {$_.FullName -ceq $Name}}
  if($length -eq 512MB){$result=Read-AriaArchiveManifest $archive;Check ($result.totalBytes -eq ($length+2)) '512 MB backup rejected'}
  else{MustReject {Read-AriaArchiveManifest $archive} '限制'}
 }
 Write-Output "Media size boundary checks passed: $script:Count"
}finally{
 foreach($name in @('synthetic.mp4','import-policy.json')){$path=Join-Path $fixture $name;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
 [IO.Directory]::Delete($fixture)
}
