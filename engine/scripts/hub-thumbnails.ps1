function Get-AriaVideoPosterTime {
  param([string]$Path,[string]$FFmpeg)
  # Sample original timestamps so the final seek matches the scored frame.
  $filter="select='isnan(prev_selected_t)+gte(t-prev_selected_t,1)',scale=160:-2,signalstats,metadata=mode=print:file=-"
  $result=Invoke-DreamSkinNative -FilePath $FFmpeg -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-t','12','-i',$Path,'-an','-sn','-dn','-vf',$filter,'-frames:v','12','-threads','1','-f','null','-') -SeparateStderr
  if($result.ExitCode -ne 0){return $null}
  $samples=[Collections.Generic.List[object]]::new();$sample=$null
  foreach($line in $result.Output){
    if($line -match '^frame:.*pts_time:([0-9.]+)'){
      if($sample){$samples.Add($sample)}
      $sample=@{time=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}
    }elseif($sample -and $line -match '^lavfi.signalstats.(YAVG|YLOW|YHIGH)=([0-9.]+)'){$sample[$Matches[1]]=[double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture)}
  }
  if($sample){$samples.Add($sample)}
  $best=$null;$bestScore=[double]::NegativeInfinity
  foreach($candidate in $samples){
    if(-not $candidate.ContainsKey('YAVG') -or -not $candidate.ContainsKey('YHIGH') -or -not $candidate.ContainsKey('YLOW')){continue}
    $brightness=$candidate.YAVG;$contrast=$candidate.YHIGH-$candidate.YLOW
    if($brightness -lt 28 -or $brightness -gt 225 -or $contrast -lt 12){continue}
    $score=$brightness+[Math]::Min(80,$contrast)*0.3-[Math]::Max(0,$brightness-190)*2
    if($score -gt $bestScore){$bestScore=$score;$best=$candidate.time}
  }
  return $best
}

function New-AriaThumbnailMutex {
  param([string]$Root)
  $hasher=[Security.Cryptography.SHA256]::Create()
  try{$rootKey=[BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Root).ToLowerInvariant()))).Replace('-','').Substring(0,20)}finally{$hasher.Dispose()}
  return [Threading.Mutex]::new($false,('Local.Aria.Thumbnails.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value+'.'+$rootKey))
}

function Write-AriaThumbnailFrame {
  param([string]$SourcePath,[string]$OutputPath,[string]$FFmpeg,$Time,[switch]$FindUsableFrame)
  Assert-DreamSkinNoReparseComponents $SourcePath
  Assert-DreamSkinNoReparseComponents $OutputPath
  $temporary=$OutputPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp.jpg'
  Assert-DreamSkinNoReparseComponents $temporary
  # Bound both dimensions and keep small originals at their native size. The
  # matte is derived from the scaled frame so transparent art keeps its shape.
  $scale="scale=w='min(960,iw)':h='min(960,ih)':force_original_aspect_ratio=decrease"
  $head=if($FindUsableFrame){'fps=4,blackframe=amount=0:threshold=24,metadata=mode=select:key=lavfi.blackframe.pblack:value=98:function=less,'}else{''}
  $filter='[0:v]'+$head+$scale+',setpts=PTS-STARTPTS,format=rgba,split[fg][bg];[bg]lutrgb=r=247:g=250:b=252,format=rgb24[matte];[matte][fg]overlay=shortest=1:format=auto,format=yuvj420p[out]'
  try{
    $arguments=@('-hide_banner','-loglevel','error','-nostdin','-y')
    if($null -ne $Time){$arguments+=@('-ss',([double]$Time).ToString('0.000',[Globalization.CultureInfo]::InvariantCulture))}
    $arguments+=@('-t','30','-i',$SourcePath,'-an','-sn','-dn','-filter_complex_threads','1','-filter_complex',$filter,'-map','[out]','-frames:v','1','-q:v','2','-threads','1',$temporary)
    $result=Invoke-DreamSkinNative -FilePath $FFmpeg -ArgumentList $arguments -SeparateStderr
    if($FindUsableFrame -and $result.ExitCode -eq 0 -and -not(Test-Path -LiteralPath $temporary)){
      # All-black clips still get a valid cover.
      $filter=$filter.Replace($head,'')
      $result=Invoke-DreamSkinNative -FilePath $FFmpeg -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-y','-i',$SourcePath,'-an','-sn','-dn','-filter_complex_threads','1','-filter_complex',$filter,'-map','[out]','-frames:v','1','-q:v','2','-threads','1',$temporary) -SeparateStderr
    }
    if($result.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $temporary) -or (Get-Item -LiteralPath $temporary).Length -lt 1){throw '这段画面暂时无法生成封面，请稍微移动播放进度后再试。'}
    Assert-DreamSkinNoReparseComponents $OutputPath
    if(Test-Path -LiteralPath $OutputPath){
      $previous=$OutputPath+'.'+[guid]::NewGuid().ToString('N')+'.previous'
      Assert-DreamSkinNoReparseComponents $previous
      [IO.File]::Replace($temporary,$OutputPath,$previous);[IO.File]::Delete($previous)
    }else{[IO.File]::Move($temporary,$OutputPath)}
  }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Set-AriaPosterMetadata {
  param($Metadata,$Source,$Time,[bool]$Manual,[bool]$Video)
  if(-not $Metadata){$Metadata=[pscustomobject]@{}}
  $Metadata|Add-Member -NotePropertyName thumbnailVersion -NotePropertyValue 1 -Force
  $Metadata|Add-Member -NotePropertyName posterBytes -NotePropertyValue $Source.Length -Force
  $Metadata|Add-Member -NotePropertyName posterModified -NotePropertyValue $Source.LastWriteTimeUtc.Ticks -Force
  if($Video){
    $Metadata|Add-Member -NotePropertyName posterVersion -NotePropertyValue 3 -Force
    $Metadata|Add-Member -NotePropertyName posterTime -NotePropertyValue $Time -Force
    $Metadata|Add-Member -NotePropertyName posterManual -NotePropertyValue $Manual -Force
  }
  return $Metadata
}

function Initialize-DreamHubThumbnails {
  param([string[]]$ThemeIds)
  $root=Join-Path $script:DreamHubHome 'thumbnails'
  Assert-DreamSkinNoReparseComponents $root
  [void][IO.Directory]::CreateDirectory($root)
  $mutex=New-AriaThumbnailMutex $root;$held=$false
  try{
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){return}
    $catalog=New-DreamSkinThemeImportMutex;$catalogHeld=$false
    try{
      try{$catalogHeld=$catalog.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$catalogHeld=$true}
      if(-not $catalogHeld){return}
      $themes=@(Get-DreamSkinSavedThemes -SkipImageMetadata)
    }finally{if($catalogHeld){$catalog.ReleaseMutex()};$catalog.Dispose()}
    foreach($theme in $themes){
      try{
        if($ThemeIds -and $theme.Id -notin $ThemeIds){continue}
        if($theme.Id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){continue}
        $loaded=Read-DreamSkinTheme $theme.Path -SkipImageMetadata
        $isVideo=[IO.Path]::GetExtension($loaded.ImagePath) -in @('.mp4','.webm')
        Assert-DreamSkinNoReparseComponents $loaded.ImagePath
        $source=Get-Item -LiteralPath $loaded.ImagePath
        $metaPath=Join-Path $root ($theme.Id+'.json');Assert-DreamSkinNoReparseComponents $metaPath
        $out=Join-Path $root ($theme.Id+'.jpg');Assert-DreamSkinNoReparseComponents $out
        $meta=Read-DreamHubJson $metaPath $null
        $sameSource=$meta -and $meta.posterBytes -eq $source.Length -and $meta.posterModified -eq $source.LastWriteTimeUtc.Ticks
        # Preserve manually selected covers for this exact source, including
        # across automatic-thumbnail algorithm updates.
        if((Test-Path -LiteralPath $out) -and $sameSource -and (($isVideo -and ($meta.posterManual -eq $true -or $meta.posterVersion -eq 3)) -or (-not $isVideo -and $meta.thumbnailVersion -eq 1))){continue}
        if(-not $meta -or (-not $sameSource -and $meta.posterBytes) -or (-not $isVideo -and $null -eq $meta.animated)){
          $node=Get-DreamSkinNodeRuntime
          $arguments=if($isVideo){@((Join-Path $PSScriptRoot 'video-metadata.mjs'),$loaded.ImagePath)}else{@((Join-Path $PSScriptRoot 'image-metadata.mjs'),'--check',$loaded.ImagePath)}
          $check=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $arguments -SeparateStderr
          if($check.ExitCode -ne 0){continue}
          $meta=($check.Output -join [Environment]::NewLine)|ConvertFrom-Json
        }
        $ffmpeg=Join-Path $script:DreamSceneTools 'bin\ffmpeg.exe'
        $manual=$false
        if($isVideo -and $sameSource -and $meta.posterManual -eq $true){
          try{$savedTime=[double]$meta.posterTime;$manual=$null -ne $meta.posterTime -and -not [double]::IsNaN($savedTime) -and -not [double]::IsInfinity($savedTime) -and $savedTime -ge 0}catch{}
        }
        $posterTime=if($manual){$savedTime}elseif($isVideo){Get-AriaVideoPosterTime -Path $loaded.ImagePath -FFmpeg $ffmpeg}else{$null}
        Write-AriaThumbnailFrame -SourcePath $loaded.ImagePath -OutputPath $out -FFmpeg $ffmpeg -Time $posterTime -FindUsableFrame:($isVideo -and $null -eq $posterTime)
        $meta=Set-AriaPosterMetadata -Metadata $meta -Source $source -Time $posterTime -Manual $manual -Video $isVideo
        Write-DreamHubJson $metaPath $meta
      }catch{if($ThemeIds){Write-Warning ($theme.Id+': '+$_.Exception.Message)}}
    }
  }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Set-AriaVideoCover {
  param([Parameter(Mandatory=$true)][string]$ThemeId,[double]$Time=0,[switch]$Reset)
  if($ThemeId -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){throw '请选择皮肤库中的视频。'}
  if([double]::IsNaN($Time) -or [double]::IsInfinity($Time) -or $Time -lt 0){throw '请选择有效的播放位置。'}
  $loaded=Get-DreamHubThemeById $ThemeId
  if([IO.Path]::GetExtension($loaded.ImagePath) -notin @('.mp4','.webm')){throw '当前画面封面适用于视频皮肤。'}
  Assert-DreamSkinNoReparseComponents $loaded.ImagePath
  $root=Join-Path $script:DreamHubHome 'thumbnails';Assert-DreamSkinNoReparseComponents $root
  [void][IO.Directory]::CreateDirectory($root)
  $mutex=New-AriaThumbnailMutex $root;$held=$false
  try{
    try{$held=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw '封面正在生成，请稍后再试。'}
    # Recheck access after waiting for the generator to finish.
    $loaded=Get-DreamHubThemeById $ThemeId
    Assert-DreamSkinNoReparseComponents $loaded.ImagePath
    $source=Get-Item -LiteralPath $loaded.ImagePath
    $ffmpeg=Join-Path $script:DreamSceneTools 'bin\ffmpeg.exe'
    $ffprobe=Join-Path $script:DreamSceneTools 'bin\ffprobe.exe'
    $probe=Invoke-DreamSkinNative -FilePath $ffprobe -ArgumentList @('-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',$loaded.ImagePath) -SeparateStderr
    $duration=0.0
    if($probe.ExitCode -ne 0 -or -not [double]::TryParse(($probe.Output -join '').Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -or [double]::IsNaN($duration) -or [double]::IsInfinity($duration) -or $duration -le 0){throw '暂时无法读取视频时长，请重新打开预览后再试。'}
    if(-not $Reset -and $Time -gt $duration){throw '封面位置超出视频时长，请重新选择。'}
    $metaPath=Join-Path $root ($ThemeId+'.json');Assert-DreamSkinNoReparseComponents $metaPath
    $out=Join-Path $root ($ThemeId+'.jpg');Assert-DreamSkinNoReparseComponents $out
    $meta=Read-DreamHubJson $metaPath $null
    if(-not $meta -or $meta.posterBytes -ne $source.Length -or $meta.posterModified -ne $source.LastWriteTimeUtc.Ticks){
      $node=Get-DreamSkinNodeRuntime
      $check=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList @((Join-Path $PSScriptRoot 'video-metadata.mjs'),$loaded.ImagePath) -SeparateStderr
      if($check.ExitCode -ne 0){throw '暂时无法读取视频资料，请重新导入后再试。'}
      $meta=($check.Output -join [Environment]::NewLine)|ConvertFrom-Json
    }
    $posterTime=if($Reset){Get-AriaVideoPosterTime -Path $loaded.ImagePath -FFmpeg $ffmpeg}else{[Math]::Min($Time,[Math]::Max([double]0,$duration-0.1))}
    Write-AriaThumbnailFrame -SourcePath $loaded.ImagePath -OutputPath $out -FFmpeg $ffmpeg -Time $posterTime -FindUsableFrame:($Reset -and $null -eq $posterTime)
    $meta=Set-AriaPosterMetadata -Metadata $meta -Source $source -Time $posterTime -Manual (-not $Reset) -Video $true
    Write-DreamHubJson $metaPath $meta
    return [pscustomobject]@{message=$(if($Reset){'已恢复自动亮帧封面'}else{'已保存当前画面为封面'})}
  }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
