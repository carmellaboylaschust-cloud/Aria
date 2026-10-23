$script:DreamHubRoot='D:\Aria\user-backgrounds'
function Get-DreamHubPolicy {
  $path=Join-Path $script:DreamHubRoot 'import-policy.json'
  $defaults=[pscustomobject]@{videoMaxMB=256;imageMaxMB=32;sceneMaxMB=512;minFreeMB=2048;recordSeconds=20;autoImportWorkshop=$false}
  if(Test-Path -LiteralPath $path){
    try{
      $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
      foreach($key in @('videoMaxMB','imageMaxMB','sceneMaxMB','minFreeMB','recordSeconds')){
        if($saved.PSObject.Properties[$key]){$defaults.$key=[int]$saved.$key}
      }
      if($saved.PSObject.Properties['autoImportWorkshop'] -and $saved.autoImportWorkshop -is [bool]){$defaults.autoImportWorkshop=$saved.autoImportWorkshop}
    }catch{}
  }
  $defaults.videoMaxMB=[Math]::Max(16,[Math]::Min(512,$defaults.videoMaxMB))
  $defaults.imageMaxMB=[Math]::Max(1,[Math]::Min(32,$defaults.imageMaxMB))
  $defaults.sceneMaxMB=[Math]::Max(16,[Math]::Min(1024,$defaults.sceneMaxMB))
  $defaults.recordSeconds=[Math]::Max(10,[Math]::Min(60,$defaults.recordSeconds))
  return $defaults
}
function Assert-DreamHubFreeSpace {
  $policy=Get-DreamHubPolicy
  $drive=[IO.DriveInfo]::new('D:\')
  if($drive.AvailableFreeSpace -lt ([long]$policy.minFreeMB*1MB)){throw 'D 盘剩余空间不足 2 GB，已停止导入和录制。'}
}
function Assert-DreamHubMediaPolicy {
  param([string]$Path)
  Assert-DreamSkinNoReparseComponents -Path $Path
  $item=Get-Item -LiteralPath $Path -ErrorAction Stop
  $ext=$item.Extension.ToLowerInvariant()
  $policy=Get-DreamHubPolicy
  if($ext -in @('.mp4','.webm')){
    if($item.Length -gt ([long]$policy.videoMaxMB*1MB)){throw "视频超过 $($policy.videoMaxMB) MB，已跳过，不会转换或入库。"}
    $probe='D:\Aria\tools\ffmpeg-9.0.2\bin\ffprobe.exe'
    if(Test-Path -LiteralPath $probe){
      $check=Invoke-DreamSkinNative -FilePath $probe -ArgumentList @('-v','error','-select_streams','v:0','-show_entries','stream=codec_name,width,height','-of','json',$item.FullName) -SeparateStderr
      if($check.ExitCode -ne 0){throw '视频文件损坏或不可读取。'}
      $details=($check.Output -join [Environment]::NewLine)|ConvertFrom-Json
      if(-not $details.streams.Count){throw '视频中没有可播放画面。'}
      $codec=$details.streams[0].codec_name
      if(($ext -eq '.mp4' -and $codec -notin @('h264','av1')) -or ($ext -eq '.webm' -and $codec -notin @('vp8','vp9','av1'))){throw "不支持此视频编码：$codec。允许 MP4（H.264/AV1）和 WebM（VP8/VP9/AV1）。"}
    }
  }elseif($ext -in @('.jpg','.jpeg','.png','.webp','.gif')){
    if($item.Length -gt ([long]$policy.imageMaxMB*1MB)){throw "图片或动图超过 $($policy.imageMaxMB) MB，已跳过。"}
  }else{throw '不允许此格式。可导入 JPG、PNG、WebP、GIF、MP4 和 WebM。'}
  Assert-DreamHubFreeSpace
}
function Get-DreamHubProjectFiles {
  param([string]$ProjectPath)
  $root=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ProjectPath));Assert-DreamSkinNoReparseComponents -Path $root
  # Check directories before walking them, including empty links and hidden files.
  $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
  while($pending.Count){
    $directory=$pending.Pop()
    foreach($entry in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)){
      Assert-DreamSkinNoReparseComponents -Path $entry.FullName
      if($entry.PSIsContainer){$pending.Push($entry.FullName)}else{$entry}
    }
  }
}
function Assert-DreamHubScenePolicy {
  param([string]$ProjectPath)
  $policy=Get-DreamHubPolicy
  [long]$total=0
  foreach($file in Get-DreamHubProjectFiles $ProjectPath){
    $total+=$file.Length
    if($total -gt ([long]$policy.sceneMaxMB*1MB)){throw "Scene / Web 资源超过 $($policy.sceneMaxMB) MB，已跳过自动录制。"}
  }
  Assert-DreamHubFreeSpace
}
