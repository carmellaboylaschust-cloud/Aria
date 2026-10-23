param([switch]$FunctionsOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'background-library.ps1')
. (Join-Path $PSScriptRoot 'scene-queue.ps1')
. (Join-Path $PSScriptRoot 'hub-workshop.ps1')
. (Join-Path $PSScriptRoot 'scene-background.ps1')

function Invoke-SceneRecording {
  param($Job)
  $recorder=$null;$stderr=$null;$partial=$null;$backgroundGuard=$null
  try{
    if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
    Assert-DreamSceneTools
    $project=Read-DreamSceneProject $Job.projectPath
    $Job|Add-Member -NotePropertyName projectType -NotePropertyValue $project.Type -Force
    Assert-DreamHubScenePolicy $Job.projectPath
    $sourceRevision=Get-AriaWorkshopSourceRevision $Job.projectPath
    if($Job.seconds -lt 5 -or $Job.seconds -gt 120 -or $Job.appearance -notin @('light','dark')){throw '任务参数无效。'}
    $Job.status='starting';$Job.percent=1;$Job.message=$(if($project.Type -eq 'web'){'正在后台准备 Web 网页'}else{'正在后台准备 Scene 场景'});$Job.error=''
    $Job.workerPid=$PID;$Job.workerStartedAt=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    $Job.windowTitle='AriaCapture-'+$Job.id
    $backgroundGuard=Start-AriaSceneBackgroundWindow -Title $Job.windowTitle
    Save-DreamSceneJob $Job
    $engine=Get-DreamSceneEngineExecutable -EnsureRunning
    if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
    $result=Invoke-DreamSkinNative -FilePath $engine -ArgumentList @('-control','openWallpaper','-file',$project.RenderPath,'-playInWindow',$Job.windowTitle,'-width','1920','-height','1080','-x',([string]$backgroundGuard.X),'-y',([string]$backgroundGuard.Y),'-borderless') -SeparateStderr
    if($result.ExitCode -ne 0){throw 'Wallpaper Engine 未接受 Scene / Web 独立录制窗口，请确认引擎正常后重试。'}
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    $handle=[IntPtr]::Zero
    while($handle -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $deadline){
      if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
      Start-Sleep -Milliseconds 300
      $handle=Get-DreamSceneOwnedWindow $Job.windowTitle
    }
    if($handle -eq [IntPtr]::Zero){throw 'Wallpaper Engine 未打开 Scene / Web 录制窗口。请确认 Steam 和 Wallpaper Engine 可以正常运行后重试。'}
    # Local Web runtimes can initialize asynchronously after the HWND appears.
    # Give Web five seconds to initialize, while keeping cancellation responsive.
    $warmupSeconds=if($project.Type -eq 'web'){5}else{3}
    $warmupDeadline=[DateTime]::UtcNow.AddSeconds($warmupSeconds)
    while([DateTime]::UtcNow -lt $warmupDeadline){
      if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
      if(-not [DreamSceneWindow]::IsWindow($handle)){throw 'Scene / Web 录制窗口被关闭，录制已停止。'}
      Start-Sleep -Milliseconds 200
    }
    $ffmpeg=Join-Path $script:DreamSceneTools 'bin\ffmpeg.exe'
    $ffprobe=Join-Path $script:DreamSceneTools 'bin\ffprobe.exe'
    $output=Get-DreamSceneJobPath $Job.id 'captures'
    $partial=[IO.Path]::ChangeExtension($output,'partial.mp4')
    Assert-DreamSkinNoReparseComponents -Path $partial
    $progress=Join-Path (Join-Path $script:DreamSceneQueueRoot 'logs') ($Job.id+'.progress')
    Assert-DreamSkinNoReparseComponents -Path $progress
    # HWND selection is mandatory. Never fall back to monitor/desktop capture.
    $filter='gfxcapture=hwnd='+$handle.ToInt64()+':max_framerate=30:capture_cursor=0:width=1920:height=1080:resize_mode=scale_aspect,hwdownload,format=bgra,setpts=PTS-STARTPTS,fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p'
    $maxBytes=[long](Get-DreamHubPolicy).videoMaxMB*1MB
    $arguments=@('-hide_banner','-nostdin','-y','-loglevel','warning','-filter_complex',$filter,'-t',"$($Job.seconds)",'-an','-c:v','libx264','-preset','veryfast','-crf','20','-threads','4','-pix_fmt','yuv420p','-movflags','+faststart','-progress',$progress,'-nostats','-fs',([string]$maxBytes),$partial)
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$ffmpeg;$info.Arguments=ConvertTo-DreamSkinArgumentLine $arguments
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardError=$true;$info.RedirectStandardOutput=$true
    $info.StandardErrorEncoding=[Text.Encoding]::UTF8
    $recorder=[Diagnostics.Process]::Start($info)
    $stderr=$recorder.StandardError.ReadToEndAsync();$stdout=$recorder.StandardOutput.ReadToEndAsync()
    try{$recorder.PriorityClass='BelowNormal'}catch{}
    $Job.status='recording';$Job.percent=5;$Job.message='正在录制，可继续使用 Codex';Save-DreamSceneJob $Job
    $started=[DateTime]::UtcNow;$lastAdvance=$started;$lastTime=-1.0
    while(-not $recorder.HasExited){
      if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
      if(-not [DreamSceneWindow]::IsWindow($handle)){throw 'Scene / Web 录制窗口被关闭，录制已停止。'}
      if([DreamSceneWindow]::IsIconic($handle)){throw 'Scene / Web 录制窗口被最小化，请重试。'}
      if(([DateTime]::UtcNow-$started).TotalSeconds -gt ($Job.seconds+60)){throw '录制超时，请确认 Scene / Web 壁纸能正常播放后重试。'}
      if(Test-Path -LiteralPath $progress){
        $data='';try{$stream=[IO.File]::Open($progress,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);try{$reader=[IO.StreamReader]::new($stream);$data=$reader.ReadToEnd();$reader.Dispose()}finally{$stream.Dispose()}}catch [IO.IOException]{}
        $matches=[regex]::Matches($data,'(?m)^out_time_us=(\d+)')
        if($matches.Count){
          $seconds=[double]$matches[$matches.Count-1].Groups[1].Value/1000000
          if($seconds -gt $lastTime){$lastTime=$seconds;$lastAdvance=[DateTime]::UtcNow}
          $Job.percent=[int][Math]::Min(94,5+90*$seconds/$Job.seconds)
          $Job.message='正在录制 '+[int][Math]::Min($Job.seconds,$seconds)+' / '+$Job.seconds+' 秒'
          Save-DreamSceneJob $Job
        }
      }
      Assert-DreamHubFreeSpace
      if(([DateTime]::UtcNow-$lastAdvance).TotalSeconds -gt 25){throw 'Scene / Web 壁纸长时间没有输出画面。请解锁屏幕并确认壁纸能播放后重试。'}
      Start-Sleep -Milliseconds 500
    }
    $recorder.WaitForExit()
    $errorText=$stderr.Result
    [IO.File]::WriteAllText((Get-DreamSceneJobPath $Job.id 'logs'),$errorText,[Text.Encoding]::UTF8)
    if($recorder.ExitCode -ne 0){throw ('录制失败：'+($errorText -split '\r?\n'|Select-Object -Last 5)-join ' ')}
    $Job.status='finalizing';$Job.percent=95;$Job.message='检查视频并加入皮肤库';Save-DreamSceneJob $Job
    if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
    $probe=Invoke-DreamSkinNative -FilePath $ffprobe -ArgumentList @('-v','error','-select_streams','v:0','-show_entries','stream=width,height,codec_name:format=duration','-of','json',$partial) -SeparateStderr
    if($probe.ExitCode -ne 0){throw '录制文件无法读取。'}
    $metadata=($probe.Output -join "`n")|ConvertFrom-Json
    $Job|Add-Member -NotePropertyName captureMetadata -NotePropertyValue @{width=$metadata.streams[0].width;height=$metadata.streams[0].height;duration=[double]$metadata.format.duration;expectedSeconds=$Job.seconds} -Force
    if($metadata.streams[0].width -ne 1920 -or $metadata.streams[0].height -ne 1080){throw ('录制尺寸未达到 1080p：'+$metadata.streams[0].width+' × '+$metadata.streams[0].height+'。请重试。')}
    if([double]$metadata.format.duration -lt ($Job.seconds-0.5)){
      if((Get-Item -LiteralPath $partial).Length -ge $maxBytes*0.98){throw '录制达到了视频大小上限，时长不足；可缩短录制时长后重试。'}
      throw ('录制时长不足：实际 '+[Math]::Round([double]$metadata.format.duration,2)+' 秒，目标 '+$Job.seconds+' 秒。请重试。')
    }
    # Reject an entirely black DirectX capture instead of importing a broken skin.
    $black=Invoke-DreamSkinNative -FilePath $ffmpeg -ArgumentList @('-hide_banner','-i',$partial,'-vf','blackdetect=d=1:pix_th=0.02:pic_th=0.99','-an','-f','null','-') -SeparateStderr
    if($black.ExitCode -ne 0){throw '录制文件无法完整解码，已停止导入，请重试。'}
    $blackText=$black.ErrorOutput -join "`n"
    $segments=[regex]::Matches($blackText,'black_duration:([0-9.]+)')
    foreach($segment in $segments){if([double]$segment.Groups[1].Value -ge ($Job.seconds-1)){throw '录到的画面全黑，已保留日志并停止导入。'}}
    if((Get-AriaWorkshopSourceRevision $Job.projectPath) -cne $sourceRevision){throw 'Scene / Web 壁纸资源在录制期间发生变化，请下载完成后重试。'}
    if(Test-Path -LiteralPath (Get-DreamSceneJobPath $Job.id 'cancel')){throw [OperationCanceledException]::new('已取消')}
    Move-Item -LiteralPath $partial -Destination $output
    $partial=$null
    Assert-DreamHubMediaPolicy $output
    $import=Import-DreamSkinLocalMedia -Path $output -Appearance $Job.appearance
    if(-not $import.AlreadyExists){$import.Theme.name=$Job.name+$(if($project.Type -eq 'web'){'（1080p Web 录像）'}else{'（1080p 场景录像）'})}
    $import.Theme|Add-Member -NotePropertyName sourceSceneProject -NotePropertyValue $Job.projectPath -Force
    $import.Theme|Add-Member -NotePropertyName sourceProjectType -NotePropertyValue $project.Type -Force
    if($Job.workshopId){$import.Theme|Add-Member -NotePropertyName sourceWorkshopId -NotePropertyValue $Job.workshopId -Force;$import.Theme|Add-Member -NotePropertyName sourceWorkshopRevision -NotePropertyValue $sourceRevision -Force}
    Write-DreamSkinTheme -ThemeDirectory $import.Directory -Theme $import.Theme
    $Job.outputPath=$output;$Job.themeDirectory=$import.Directory;$Job|Add-Member -NotePropertyName themeId -NotePropertyValue $import.Theme.id -Force
    $Job.status='completed';$Job.percent=100;$Job.message='已加入皮肤库，可选择应用'
  }catch [OperationCanceledException]{
    $Job.status='cancelled';$Job.message='已取消';$Job.error=''
  }catch{
    $Job.status='failed';$Job.error=$_.Exception.Message;$Job.message=$Job.error
    try{[IO.File]::AppendAllText((Get-DreamSceneJobPath $Job.id 'logs'),"`r`n"+($_|Out-String),[Text.Encoding]::UTF8)}catch{}
  }finally{
    if($recorder){
      try{if(-not $recorder.HasExited){$recorder.Kill();$recorder.WaitForExit()}}catch{}
      $recorder.Dispose()
    }
    if($partial -and (Test-Path -LiteralPath $partial)){[IO.File]::Delete($partial)}
    try{Close-DreamSceneWindow $Job.windowTitle}catch{}
    if($backgroundGuard){$Job|Add-Member -NotePropertyName recordingWindow -NotePropertyValue @{offscreen=$backgroundGuard.IsOffscreen;taskbarSuppressed=$backgroundGuard.TaskbarSuppressed;foregroundObserved=$backgroundGuard.ForegroundObserved} -Force;$backgroundGuard.Dispose()}
    Save-DreamSceneJob $Job
  }
}

if($FunctionsOnly){return}
Initialize-DreamSceneQueue
$workerLock=Enter-DreamSceneMutex 'Worker' 0
if(-not $workerLock){exit 0}
try{
  # The single worker owns all status writes. An abandoned job is explicit and
  # retryable; never silently re-record after a crash or machine restart.
  foreach($job in @(Get-DreamSceneJobs|Where-Object {$_.status -in @('starting','recording','finalizing')})){
    try{Close-DreamSceneWindow $job.windowTitle}catch{}
    $job.status='failed';$job.error='上次录制被中断，请点击重试。';$job.message=$job.error;Save-DreamSceneJob $job
  }
  $null=Repair-AriaWorkshopImportResults
  $idleSince=[DateTime]::UtcNow
  while($true){
    $guard=Enter-DreamSceneMutex 'Queue'
    if(-not $guard){Start-Sleep -Milliseconds 500;continue}
    $next=$null;$stop=$false
    Update-DreamHubWaitingJobs
    Update-DreamHubWorkshopSubscriptions
    try{
      $pending=@(Get-DreamSceneJobs|Where-Object {$_.status -eq 'queued'})
      if($pending.Count){$next=$pending[0]}
      elseif(([DateTime]::UtcNow-$idleSince).TotalSeconds -gt 20 -and -not (Get-DreamHubPolicy).autoImportWorkshop -and -not @(Get-DreamSceneJobs|Where-Object {$_.status -eq 'waiting-download'}).Count){
        # Release under the same lock as enqueueing so no final enqueue is lost.
        Exit-DreamSceneMutex $workerLock;$workerLock=$null;$stop=$true
      }
    }finally{Exit-DreamSceneMutex $guard}
    if($stop){break}
    if($next){if($next.kind -eq 'workshop'){Invoke-DreamHubWorkshopImport $next}else{Invoke-SceneRecording $next};$idleSince=[DateTime]::UtcNow}else{Start-Sleep -Milliseconds 1500}
  }
}finally{Exit-DreamSceneMutex $workerLock}
