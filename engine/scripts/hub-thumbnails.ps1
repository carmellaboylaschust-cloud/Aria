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

function Initialize-DreamHubThumbnails {
  param([string[]]$ThemeIds)
  $root=Join-Path $script:DreamHubHome 'thumbnails'
  Assert-DreamSkinNoReparseComponents $root
  [void][IO.Directory]::CreateDirectory($root)
  $hasher=[Security.Cryptography.SHA256]::Create()
  try{$rootKey=[BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($root).ToLowerInvariant()))).Replace('-','').Substring(0,20)}finally{$hasher.Dispose()}
  $mutex=[Threading.Mutex]::new($false,('Local.Aria.Thumbnails.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value+'.'+$rootKey))
  $held=$false
  try{
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){return}
    $catalog=New-DreamSkinThemeImportMutex
    $catalogHeld=$false
    try{
      try{$catalogHeld=$catalog.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$catalogHeld=$true}
      if(-not $catalogHeld){return}
      $themes=@(Get-DreamSkinSavedThemes -SkipImageMetadata)
    }finally{if($catalogHeld){$catalog.ReleaseMutex()};$catalog.Dispose()}
    foreach($theme in $themes){
      $temporary=$null
      try{
        if($ThemeIds -and $theme.Id -notin $ThemeIds){continue}
        if($theme.Id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){continue}
        $loaded=Read-DreamSkinTheme $theme.Path -SkipImageMetadata
        $isVideo=[IO.Path]::GetExtension($loaded.ImagePath) -in @('.mp4','.webm')
        $metaPath=Join-Path $root ($theme.Id+'.json')
        $meta=Read-DreamHubJson $metaPath $null
        if(-not $meta -or (-not $isVideo -and $null -eq $meta.animated)){
          $node=Get-DreamSkinNodeRuntime
          $arguments=if($isVideo){@((Join-Path $PSScriptRoot 'video-metadata.mjs'),$loaded.ImagePath)}else{@((Join-Path $PSScriptRoot 'image-metadata.mjs'),'--check',$loaded.ImagePath)}
          $check=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $arguments -SeparateStderr
          if($check.ExitCode -eq 0){$meta=($check.Output -join [Environment]::NewLine)|ConvertFrom-Json;Write-DreamHubJson $metaPath $meta}
        }
        if(-not $isVideo -and -not $meta.animated){continue}
        $out=Join-Path $root ($theme.Id+'.jpg')
        $source=Get-Item -LiteralPath $loaded.ImagePath
        if((Test-Path -LiteralPath $out) -and (-not $isVideo -or ($meta.posterVersion -eq 3 -and $meta.posterBytes -eq $source.Length -and $meta.posterModified -eq $source.LastWriteTimeUtc.Ticks))){continue}
        $temporary=Join-Path $root ($theme.Id+'.'+[guid]::NewGuid().ToString('N')+'.tmp.jpg')
        $filter=if($isVideo){'fps=4,scale=960:-2,blackframe=amount=0:threshold=24,metadata=mode=select:key=lavfi.blackframe.pblack:value=98:function=less'}else{'scale=640:-2'}
        $ffmpeg=Join-Path $script:DreamSceneTools 'bin\ffmpeg.exe'
        $posterTime=if($isVideo){Get-AriaVideoPosterTime -Path $loaded.ImagePath -FFmpeg $ffmpeg}else{$null}
        $arguments=@('-hide_banner','-loglevel','error','-nostdin','-y')
        if($null -ne $posterTime){$arguments+=@('-ss',([double]$posterTime).ToString('0.000',[Globalization.CultureInfo]::InvariantCulture));$filter='scale=960:-2'}
        $arguments+=@('-t','30','-i',$loaded.ImagePath,'-an','-frames:v','1','-vf',$filter,'-q:v','2','-threads','1',$temporary)
        $result=Invoke-DreamSkinNative -FilePath $ffmpeg -ArgumentList $arguments -SeparateStderr
        # All-black clips still receive a valid first-frame image.
        if($isVideo -and $result.ExitCode -eq 0 -and -not(Test-Path -LiteralPath $temporary)){
          $result=Invoke-DreamSkinNative -FilePath $ffmpeg -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-y','-i',$loaded.ImagePath,'-an','-frames:v','1','-vf','scale=960:-2','-q:v','2','-threads','1',$temporary) -SeparateStderr
        }
        if($result.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $temporary) -or (Get-Item -LiteralPath $temporary).Length -lt 1){continue}
        Assert-DreamSkinNoReparseComponents $out
        if(Test-Path -LiteralPath $out){$previous=$out+'.'+[guid]::NewGuid().ToString('N')+'.previous';[IO.File]::Replace($temporary,$out,$previous);[IO.File]::Delete($previous)}else{[IO.File]::Move($temporary,$out)}
        $temporary=$null
        if($isVideo -and $meta){
          $meta|Add-Member -NotePropertyName posterVersion -NotePropertyValue 3 -Force
          $meta|Add-Member -NotePropertyName posterTime -NotePropertyValue $posterTime -Force
          $meta|Add-Member -NotePropertyName posterBytes -NotePropertyValue $source.Length -Force
          $meta|Add-Member -NotePropertyName posterModified -NotePropertyValue $source.LastWriteTimeUtc.Ticks -Force
          Write-DreamHubJson $metaPath $meta
        }
      }catch{if($ThemeIds){Write-Warning ($theme.Id+': '+$_.Exception.Message)}}finally{if($temporary -and [IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    }
  }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
