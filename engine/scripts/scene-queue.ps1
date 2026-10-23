. (Join-Path $PSScriptRoot 'hub-policy.ps1')
# Shared queue storage. A job has one writer (the worker); cancellation uses a
# separate marker so the UI cannot overwrite a concurrent progress update.
$script:DreamSceneQueueRoot='D:\Aria\user-backgrounds\scene-jobs'
$script:DreamSceneTools='D:\Aria\tools\ffmpeg-9.0.2'
$script:DreamSceneEngine=''
$ariaCaptureConfig='D:\Aria\user-backgrounds\capture-settings.json'
if(Test-Path -LiteralPath $ariaCaptureConfig){$script:DreamSceneEngine=[string]((Get-Content -LiteralPath $ariaCaptureConfig -Raw -Encoding UTF8|ConvertFrom-Json).wallpaperEngine)}
$script:DreamSceneScripts=$PSScriptRoot

function Initialize-DreamSceneQueue {
  foreach($part in @('jobs','captures','logs','cancel')){
    $path=Join-Path $script:DreamSceneQueueRoot $part
    Assert-DreamSkinNoReparseComponents -Path $path
    [void][IO.Directory]::CreateDirectory($path)
  }
}
function Enter-DreamSceneMutex {
  param([string]$Name,[int]$Timeout=5000)
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex=[Threading.Mutex]::new($false,"Local\Aria.$sid.Scene.$Name")
  try{$held=$mutex.WaitOne($Timeout)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(-not $held){$mutex.Dispose();return $null}
  return $mutex
}
function Exit-DreamSceneMutex {param($Mutex) if($Mutex){$Mutex.ReleaseMutex();$Mutex.Dispose()}}
function Get-DreamSceneJobPath {
  param([string]$Id,[string]$Kind='jobs')
  if($Id -cnotmatch '^[a-f0-9]{32}$' -or $Kind -notin @('jobs','cancel','captures','logs')){throw '任务编号无效。'}
  $extension=if($Kind -eq 'jobs'){'.json'}elseif($Kind -eq 'captures'){'.mp4'}elseif($Kind -eq 'logs'){'.txt'}else{'.cancel'}
  $path=Join-Path (Join-Path $script:DreamSceneQueueRoot $Kind) ($Id+$extension)
  Assert-DreamSkinNoReparseComponents -Path $path
  return $path
}
function Save-DreamSceneJob {
  param($Job)
  $Job.updatedAt=[DateTime]::UtcNow.ToString('o')
  Write-DreamSkinUtf8FileAtomically -Path (Get-DreamSceneJobPath $Job.id) -Content (($Job|ConvertTo-Json -Depth 8)+"`r`n")
}
function Get-DreamSceneJobs {
  if(-not(Test-Path -LiteralPath (Join-Path $script:DreamSceneQueueRoot 'jobs'))){return @()}
  @(Get-ChildItem -LiteralPath (Join-Path $script:DreamSceneQueueRoot 'jobs') -Filter '*.json' -File | ForEach-Object {
    try{
      $job=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json
      if($job.schemaVersion -eq 1 -and $job.id -ceq $_.BaseName -and $job.id -cmatch '^[a-f0-9]{32}$'){$job}
    }catch{}
  }|Sort-Object createdAt,id)
}
function Read-DreamSceneProject {
  param([string]$Path)
  $full=[IO.Path]::GetFullPath($Path)
  Assert-DreamSkinNoReparseComponents -Path $full
  if($full.StartsWith('\\') -or [IO.Path]::GetFileName($full) -ine 'project.json' -or -not(Test-Path -LiteralPath $full -PathType Leaf)){throw '请选择本地 Wallpaper Engine Scene 场景或 Web 网页的 project.json。'}
  if((Get-Item -LiteralPath $full).Length -gt 2MB){throw 'Scene / Web 壁纸说明文件过大。'}
  $project=Get-Content -LiteralPath $full -Raw -Encoding UTF8|ConvertFrom-Json
  $type=([string]$project.type).ToLowerInvariant()
  if($type -notin @('scene','web')){throw '此功能用于 Scene 场景和 Web 网页。已有视频可直接使用“添加背景”。'}
  $folder=[IO.Path]::GetDirectoryName($full)
  $renderPath=$full
  if($type -eq 'web'){
    # Only a local HTML entry can be given to the installed official renderer.
    # Never hand a project-supplied URL, executable, ADS or escaped path to it.
    $relative=[string]$project.file
    if(-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '[:<>"|?*#\x00-\x1f]' -or @($relative -split '[\\/]'|Where-Object {$_ -eq '..'}).Count){throw 'Web 网页入口必须是壁纸目录内的本地 HTML 文件。'}
    $renderPath=[IO.Path]::GetFullPath((Join-Path $folder $relative))
    if(-not $renderPath.StartsWith($folder.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($renderPath).ToLowerInvariant() -notin @('.html','.htm')){throw 'Web 网页入口必须是壁纸目录内的本地 HTML 文件。'}
    Assert-DreamSkinNoReparseComponents -Path $renderPath
    if(-not(Test-Path -LiteralPath $renderPath -PathType Leaf)){throw '找不到 Web 网页入口，请先在 Steam 中完成下载。'}
  }else{
    $package=Join-Path $folder 'scene.pkg'
    $loose=Join-Path $folder 'scene.json'
    if(-not(Test-Path -LiteralPath $package -PathType Leaf) -and -not(Test-Path -LiteralPath $loose -PathType Leaf)){throw '找不到 Scene 场景内容，请先在 Steam 中完成下载。'}
    if(Test-Path -LiteralPath $package -PathType Leaf){Assert-DreamSkinNoReparseComponents -Path $package}
    if(Test-Path -LiteralPath $loose -PathType Leaf){Assert-DreamSkinNoReparseComponents -Path $loose}
  }
  $name="$($project.title)".Trim()
  if(-not $name){$name=Split-Path $folder -Leaf}
  if($name.Length -gt 60){$name=$name.Substring(0,60)}
  [pscustomobject]@{Path=$full;Name=$name;Type=$type;RenderPath=$renderPath}
}
function Assert-DreamSceneTools {
  $manifestPath=Join-Path $script:DreamSceneTools 'verified.json'
  if(-not(Test-Path -LiteralPath $manifestPath)){throw '1080p 录制组件尚未准备好。'}
  $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($name in @('bin/ffmpeg.exe','bin/ffprobe.exe')){
    $path=Join-Path $script:DreamSceneTools $name
    Assert-DreamSkinNoReparseComponents -Path $path
    if(-not(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $manifest.files.PSObject.Properties[$name].Value){throw '录制组件校验未通过，请重新准备组件。'}
  }
  if(-not(Test-Path -LiteralPath $script:DreamSceneEngine -PathType Leaf)){throw '找不到已安装的 Wallpaper Engine。'}
}
function Start-DreamSceneWorker {
  $worker=Join-Path $script:DreamSceneScripts 'scene-worker.ps1'
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $info.Arguments=ConvertTo-DreamSkinArgumentLine @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',$worker)
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
  $child=[Diagnostics.Process]::Start($info)
  $child.Dispose()
}
function Add-DreamSceneJob {
  param([string]$ProjectPath,[ValidateRange(5,120)][int]$Seconds=20,[ValidateSet('light','dark')][string]$Appearance='dark',[switch]$TestOnly)
  $project=Read-DreamSceneProject $ProjectPath
  Assert-DreamHubScenePolicy $project.Path
  Initialize-DreamSceneQueue
  $guard=Enter-DreamSceneMutex 'Queue'
  if(-not $guard){throw '任务列表正忙，请稍后重试。'}
  try{
    $existing=@(Get-DreamSceneJobs|Where-Object {$_.projectPath -ieq $project.Path -and $_.seconds -eq $Seconds -and $_.status -in @('queued','starting','recording','finalizing') -and -not(Test-Path -LiteralPath (Get-DreamSceneJobPath $_.id 'cancel'))})
    if($existing.Count){Start-DreamSceneWorker;return $existing[0]}
    $job=[pscustomobject]@{
      schemaVersion=1;id=[guid]::NewGuid().ToString('N');testOnly=[bool]$TestOnly;name=$project.Name;projectPath=$project.Path;projectType=$project.Type
      seconds=$Seconds;appearance=$Appearance;status='queued';percent=0;message='等待录制';createdAt=[DateTime]::UtcNow.ToString('o');updatedAt=''
      outputPath='';themeDirectory='';workerPid=0;workerStartedAt='';windowTitle='';error=''
    }
    Save-DreamSceneJob $job
    Start-DreamSceneWorker
    return $job
  }finally{Exit-DreamSceneMutex $guard}
}
function Stop-DreamSceneJob {
  param([string]$Id)
  Initialize-DreamSceneQueue
  [IO.File]::WriteAllText((Get-DreamSceneJobPath $Id 'cancel'),'cancel')
  Start-DreamSceneWorker
}
function Show-DreamSceneQueueWindow {
  $ui=Join-Path $script:DreamSceneScripts 'scene-queue-ui.ps1'
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $info.Arguments=ConvertTo-DreamSkinArgumentLine @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',$ui)
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
  $child=[Diagnostics.Process]::Start($info);$child.Dispose()
}
function Initialize-DreamSceneWindowApi {
  if('DreamSceneWindow' -as [type]){return}
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DreamSceneWindow {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
 public static IntPtr FindByTitle(string title){return FindWindow(null,title);}
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
}
'@
}
function Get-DreamSceneOwnedWindow {
  param([string]$Title)
  Initialize-DreamSceneWindowApi
  $handle=[DreamSceneWindow]::FindByTitle($Title)
  if($handle -eq [IntPtr]::Zero){return [IntPtr]::Zero}
  [uint32]$windowPid=0
  [void][DreamSceneWindow]::GetWindowThreadProcessId($handle,[ref]$windowPid)
  try{
    $path=(Get-Process -Id $windowPid -ErrorAction Stop).Path
    if(-not(Test-DreamSceneRendererExecutable $path)){throw '窗口归属不符。'}
  }catch{throw '无法确认录制窗口属于 Wallpaper Engine，已停止。'}
  return $handle
}
function Test-DreamSceneRendererExecutable {
  param([string]$Path)
  if(-not $Path){return $false}
  $full=[IO.Path]::GetFullPath($Path);$directory=[IO.Path]::GetDirectoryName($script:DreamSceneEngine)
  $name=[IO.Path]::GetFileName($full);$parent=[IO.Path]::GetDirectoryName($full)
  if($parent -ieq $directory -and $name -in @('wallpaper32.exe','wallpaper64.exe')){return $true}
  return ($parent -ieq (Join-Path $directory 'bin') -and $name -in @('webwallpaper32.exe','webwallpaper64.exe','edgewallpaper32.exe','edgewallpaper64.exe'))
}
function Close-DreamSceneWindow {
  param([string]$Title)
  if($Title -cmatch '^(?:CodexScene|AriaCapture)-[a-f0-9]{32}$'){
    $null=Invoke-DreamSkinNative -FilePath (Get-DreamSceneEngineExecutable) -ArgumentList @('-control','closeWallpaper','-location',$Title) -SeparateStderr
  }
}

function Get-DreamSceneEngineExecutable {
  param([switch]$EnsureRunning)
  $directory=[IO.Path]::GetDirectoryName($script:DreamSceneEngine)
  $found=@(Get-Process -Name wallpaper32,wallpaper64 -ErrorAction SilentlyContinue|Where-Object {try{[IO.Path]::GetDirectoryName($_.Path) -ieq $directory}catch{$false}})
  if(-not $found.Count -and $EnsureRunning){
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$script:DreamSceneEngine;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
    $child=[Diagnostics.Process]::Start($info);$child.Dispose()
    $end=[DateTime]::UtcNow.AddSeconds(20)
    while(-not $found.Count -and [DateTime]::UtcNow -lt $end){
      Start-Sleep -Milliseconds 500
      $found=@(Get-Process -Name wallpaper32,wallpaper64 -ErrorAction SilentlyContinue|Where-Object {try{[IO.Path]::GetDirectoryName($_.Path) -ieq $directory}catch{$false}})
    }
    Start-Sleep -Seconds 2
  }
  if($found.Count){return $found[0].Path}
  throw 'Wallpaper Engine 无法启动，请先在 Steam 中启动一次后重试。'
}
