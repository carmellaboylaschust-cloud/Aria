param([Parameter(Mandatory=$true)][string]$EngineRoot,[Parameter(Mandatory=$true)][string]$FFmpeg)
$ErrorActionPreference='Stop'
. (Join-Path $EngineRoot 'scripts\common-windows.ps1')
. (Join-Path $EngineRoot 'scripts\theme-windows.ps1')
. (Join-Path $EngineRoot 'scripts\hub-thumbnails.ps1')
. (Join-Path $EngineRoot 'scripts\hub-privacy-extra.ps1')
$base=Join-Path (Split-Path $EngineRoot -Parent) '.test-output'
$fixture=Join-Path $base ('video-posters-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'thumbnails'))
$script:DreamHubHome=$fixture
$script:DreamSceneTools=Split-Path (Split-Path $FFmpeg -Parent) -Parent
$script:FixtureVideo=Join-Path $fixture 'fixture.mp4'
function Read-DreamHubJson {param($Path,$Default) if(Test-Path -LiteralPath $Path){return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)};return $Default}
function Write-DreamHubJson {param($Path,$Value) [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 8))}
function Get-DreamSkinSavedThemes {param([switch]$SkipImageMetadata) [pscustomobject]@{Id='fixture';Path=$fixture}}
function Read-DreamSkinTheme {param($Path,[switch]$SkipImageMetadata) [pscustomobject]@{ImagePath=$script:FixtureVideo}}
try{
 $result=Invoke-DreamSkinNative -FilePath $FFmpeg -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-y','-f','lavfi','-i','color=black:s=320x180:r=12:d=1','-f','lavfi','-i','testsrc2=s=320x180:r=12:d=2,eq=brightness=-0.3','-f','lavfi','-i','testsrc2=s=320x180:r=12:d=2,eq=brightness=0.1','-f','lavfi','-i','color=white:s=320x180:r=12:d=1','-filter_complex','[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0','-c:v','libx264','-pix_fmt','yuv420p',$script:FixtureVideo) -SeparateStderr
 if($result.ExitCode -ne 0){throw ($result.ErrorOutput -join ' ')}
 $poster=Join-Path $fixture 'thumbnails\fixture.jpg'
 $result=Invoke-DreamSkinNative -FilePath $FFmpeg -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-y','-i',$script:FixtureVideo,'-frames:v','1',$poster) -SeparateStderr
 if($result.ExitCode -ne 0){throw ($result.ErrorOutput -join ' ')}
 Write-DreamHubJson (Join-Path $fixture 'thumbnails\fixture.json') @{width=320;height=180;kind='video'}
 $originalHash=(Get-FileHash -LiteralPath $script:FixtureVideo).Hash
 Initialize-DreamHubThumbnails -ThemeIds @('fixture')
 $metadata=Read-DreamHubJson (Join-Path $fixture 'thumbnails\fixture.json') $null
 if($metadata.posterVersion -ne 3 -or $metadata.posterTime -lt 3 -or $metadata.posterTime -ge 5){throw 'Poster should select the bright detailed scene, skipping black, dim scenes and white flashes'}
 $stamp=(Get-Item -LiteralPath $poster).LastWriteTimeUtc.Ticks
 Initialize-DreamHubThumbnails -ThemeIds @('fixture')
 if((Get-Item -LiteralPath $poster).LastWriteTimeUtc.Ticks -ne $stamp){throw 'Valid cover was rebuilt unnecessarily'}
 if((Get-FileHash -LiteralPath $script:FixtureVideo).Hash -ne $originalHash){throw 'Source video was changed'}
 if((Get-AriaPlaybackSettings).audioEnabled){throw 'Default audio should be muted'}
 Save-AriaVideoAudio -Enabled $true
 Save-AriaPlaybackSettings -Mode static
 $settings=Get-AriaPlaybackSettings
 if(-not $settings.audioEnabled -or $settings.mode -ne 'static'){throw 'Playback save lost audio preference'}
 Save-AriaVideoAudio -Enabled $false
 if((Get-AriaPlaybackSettings).audioEnabled -or (Get-AriaPlaybackSettings).mode -ne 'static'){throw 'Audio save lost playback preference'}
 Write-Output 'Poster and playback checks passed: bright detailed frame selected, black/dim/white frames skipped, cache migrated, repeat work avoided, source preserved, audio choice persisted.'
}finally{
 $full=[IO.Path]::GetFullPath($fixture)
 $expected=[IO.Path]::GetFullPath($base).TrimEnd('\')+'\'
 if($full.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('video-posters-')){Remove-Item -LiteralPath $full -Recurse -Force}
}
