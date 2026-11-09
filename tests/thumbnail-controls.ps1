param([Parameter(Mandatory=$true)][string]$EngineRoot,[Parameter(Mandatory=$true)][string]$FFmpeg,[Parameter(Mandatory=$true)][string]$NodeExe)
$ErrorActionPreference='Stop'
. (Join-Path $EngineRoot 'scripts\common-windows.ps1')
. (Join-Path $EngineRoot 'scripts\theme-windows.ps1')
. (Join-Path $EngineRoot 'scripts\hub-thumbnails.ps1')
Add-Type -AssemblyName System.Drawing
$base=Join-Path (Split-Path $EngineRoot -Parent) '.test-output'
$fixture=Join-Path $base ('thumbnail-controls-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'thumbnails'))
$script:DreamHubHome=$fixture;$script:DreamSceneTools=Split-Path (Split-Path $FFmpeg -Parent) -Parent
$script:FixtureThemes=@{};$script:AccessAllowed=$true;$script:Checks=0
function Check($condition,$message){if(-not $condition){throw $message};$script:Checks++}
function Read-DreamHubJson {param($Path,$Default) if(Test-Path -LiteralPath $Path){return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)};return $Default}
function Write-DreamHubJson {param($Path,$Value) [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 8))}
function Get-DreamSkinNodeRuntime {return [pscustomobject]@{Path=$NodeExe}}
function Get-DreamSkinSavedThemes {param([switch]$SkipImageMetadata) foreach($id in $script:FixtureThemes.Keys){[pscustomobject]@{Id=$id;Path=$id}}}
function Read-DreamSkinTheme {param($Path,[switch]$SkipImageMetadata) return [pscustomobject]@{ImagePath=$script:FixtureThemes[$Path]}}
function Get-DreamHubThemeById {param($Id) if(-not $script:AccessAllowed){throw 'Fixture access denied'};if(-not $script:FixtureThemes.ContainsKey($Id)){throw 'Fixture missing'};Read-DreamSkinTheme $Id}
function ExpectFailure([scriptblock]$Action,$message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $message}
function MakeImage($id,$width,$height,[bool]$transparent){
 $path=Join-Path $fixture ($id+'.png');$bitmap=[Drawing.Bitmap]::new($width,$height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 try{$graphics.Clear($(if($transparent){[Drawing.Color]::Transparent}else{[Drawing.Color]::CornflowerBlue}));$graphics.FillRectangle([Drawing.Brushes]::Coral,($width/4),($height/4),($width/2),($height/2));$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
 $script:FixtureThemes[$id]=$path
}
try{
 MakeImage 'large' 2400 1600 $false;MakeImage 'small' 160 100 $true;MakeImage 'portrait' 120 2400 $false
 $video=Join-Path $fixture 'clip.mp4';$script:FixtureThemes['clip']=$video
 $result=Invoke-DreamSkinNative -FilePath $FFmpeg -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-y','-f','lavfi','-i','color=black:s=320x180:r=12:d=1','-f','lavfi','-i','testsrc2=s=320x180:r=12:d=2,eq=brightness=-0.3','-f','lavfi','-i','testsrc2=s=320x180:r=12:d=2,eq=brightness=0.1','-f','lavfi','-i','color=white:s=320x180:r=12:d=1','-filter_complex','[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0','-c:v','libx264','-pix_fmt','yuv420p',$video) -SeparateStderr
 Check ($result.ExitCode -eq 0) 'Fixture video generation failed'
 $hashes=@{};foreach($id in $script:FixtureThemes.Keys){$hashes[$id]=(Get-FileHash -LiteralPath $script:FixtureThemes[$id]).Hash}
 Initialize-DreamHubThumbnails
 foreach($item in @(@('large',960,640),@('small',160,100),@('portrait',48,960))){
  $path=Join-Path $fixture ('thumbnails\'+$item[0]+'.jpg');Check (Test-Path -LiteralPath $path) ('Missing thumbnail '+$item[0])
  $bitmap=[Drawing.Bitmap]::new($path);try{Check ($bitmap.Width -eq $item[1] -and $bitmap.Height -eq $item[2]) ('Wrong bounded dimensions '+$item[0]);if($item[0] -eq 'small'){$color=$bitmap.GetPixel(1,1);Check ($color.R -ge 240 -and $color.G -ge 240 -and $color.B -ge 240) 'Transparent art needs a light matte'}}finally{$bitmap.Dispose()}
 }
 $poster=Join-Path $fixture 'thumbnails\clip.jpg';$metaPath=Join-Path $fixture 'thumbnails\clip.json'
 $meta=Read-DreamHubJson $metaPath $null;Check ($meta.posterTime -ge 3 -and $meta.posterTime -lt 5) 'Automatic cover should select bright detail'
 Set-AriaVideoCover -ThemeId clip -Time 1.5|Out-Null
 $meta=Read-DreamHubJson $metaPath $null;Check ($meta.posterManual -and $meta.posterTime -eq 1.5) 'Manual timestamp should persist'
 $stamp=(Get-Item -LiteralPath $poster).LastWriteTimeUtc.Ticks;$manualHash=(Get-FileHash -LiteralPath $poster).Hash
 Initialize-DreamHubThumbnails
 Check ((Get-Item -LiteralPath $poster).LastWriteTimeUtc.Ticks -eq $stamp) 'Background scan overwrote manual cover'
 [IO.File]::Delete($poster);Initialize-DreamHubThumbnails -ThemeIds clip
 Check ((Get-FileHash -LiteralPath $poster).Hash -eq $manualHash) 'Cache rebuild should restore chosen frame'
 Check ((Read-DreamHubJson $metaPath $null).posterManual) 'Cache rebuild should preserve manual marker'
 Set-AriaVideoCover -ThemeId clip -Reset|Out-Null
 $meta=Read-DreamHubJson $metaPath $null;Check (-not $meta.posterManual -and $meta.posterTime -ge 3 -and $meta.posterTime -lt 5) 'Reset should restore bright automatic cover'
 Set-AriaVideoCover -ThemeId clip -Time 6|Out-Null
 Check ((Read-DreamHubJson $metaPath $null).posterTime -lt 6) 'Exact endpoint should use the last decodable frame'
 foreach($time in @(-1,[double]::NaN,[double]::PositiveInfinity,9999)){ExpectFailure {Set-AriaVideoCover -ThemeId clip -Time $time} 'Invalid timestamp accepted'}
 ExpectFailure {Set-AriaVideoCover -ThemeId small -Time 0} 'Non-video accepted'
 ExpectFailure {Set-AriaVideoCover -ThemeId '../clip' -Time 0} 'Invalid theme ID accepted'
 $script:AccessAllowed=$false;ExpectFailure {Set-AriaVideoCover -ThemeId clip -Time 1} 'Locked skin access accepted';$script:AccessAllowed=$true
 foreach($id in $script:FixtureThemes.Keys){Check ((Get-FileHash -LiteralPath $script:FixtureThemes[$id]).Hash -eq $hashes[$id]) ('Source changed '+$id)}
 $imageMeta=Read-DreamHubJson (Join-Path $fixture 'thumbnails\large.json') $null;Check ($imageMeta.width -eq 2400 -and $imageMeta.height -eq 1600) 'Metadata should retain original dimensions'
 Write-Output ('Thumbnail controls: '+$script:Checks+' checks passed; bounded static images, native small size, transparency matte, manual persistence/reset, validation and source integrity.')
}catch{Write-Output $_.ScriptStackTrace;Write-Output $fixture;throw}finally{
 $full=[IO.Path]::GetFullPath($fixture);$expected=[IO.Path]::GetFullPath($base).TrimEnd('\')+'\'
 if(-not $env:ARIA_KEEP_TEST -and $full.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('thumbnail-controls-')){Remove-Item -LiteralPath $full -Recurse -Force}
}
