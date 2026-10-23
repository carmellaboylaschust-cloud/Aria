
$script:DreamHubHome='D:\Aria\user-backgrounds'
$script:DreamHubState='D:\Aria\runtime'
$script:DreamHubThemeCache=@{}
. (Join-Path $PSScriptRoot 'hub-privacy.ps1')
. (Join-Path $PSScriptRoot 'hub-library.ps1')
function Read-DreamHubJson {
  param([string]$Path,$Default)
  if(Test-Path -LiteralPath $Path){try{$value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json;return $value}catch{}}
  return $Default
}
function Write-DreamHubJson {param([string]$Path,$Value) Assert-DreamSkinNoReparseComponents $Path;Write-DreamSkinUtf8FileAtomically -Path $Path -Content ((ConvertTo-Json -InputObject $Value -Depth 12)+[Environment]::NewLine)}
function Get-DreamHubPrompts {
  $builtins=@(
    [pscustomobject]@{id='builtin-study';name='学习陪伴';category='学习 · 一起弄懂';builtin=$true;text='请做我的学习搭子。先了解我的基础和目标，用清楚的语言拆解知识点；给例子，再用小问题检查理解。解题时解释思路，避免直接跳到答案。遇到不确定的事实请说明。'},
    [pscustomobject]@{id='builtin-write';name='写作与润色';category='表达 · 把想法说清楚';builtin=$true;text='请协助我写作与润色。先明确读者、目的、语气和长度。保留原意与个人表达，使用具体、自然的语言，指出需要补充的依据，不编造事实或引用。修改后简要说明关键调整。'},
    [pscustomobject]@{id='builtin-code';name='开发小助手';category='编程 · 从想法到实现';builtin=$true;text='请协助我完成开发任务。先阅读现有项目与约束，说明关键取舍，尽量作出小而完整的改动。完成后运行适当验证，说明改了什么、测试结果和未解决的问题。不要泄露密钥，也不要未经许可部署或删除重要数据。'},
    [pscustomobject]@{id='builtin-plan';name='今日小计划';category='规划 · 慢慢做到';builtin=$true;text='请帮我把当前目标整理成可执行的小计划。先确认截止时间、已有进展和可用精力；区分必须完成与可选事项，给出合理的顺序和下一步。计划应留出休息与缓冲，避免堆满日程。'}
  )
  return @($builtins)+@(Read-DreamHubJson (Join-Path $script:DreamHubHome 'prompts.json') @())
}
function Get-DreamHubThemeById {
  param([string]$Id)
  if($Id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){throw '请选择皮肤库中的一张背景。'}
  Assert-AriaThemeVisible -Id $Id
  $mutex=New-DreamSkinThemeImportMutex;$acquired=$false
  try{
    try{$acquired=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$acquired=$true}
    if(-not $acquired){throw '皮肤库正在保存图片，请稍后再试。'}
    $entry=@(Get-DreamSkinSavedThemes -SkipImageMetadata|Where-Object {$_.Id -ceq $Id})
    if($entry.Count -ne 1){throw '找不到这张皮肤，请刷新后重试。'}
    return Read-DreamSkinTheme $entry[0].Path -SkipImageMetadata
  }finally{if($acquired){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Get-AriaMediaMappings {
 return @(
  [pscustomobject]@{host='media0.skin.local';root=(Join-Path $script:DreamHubHome 'themes')}
  [pscustomobject]@{host='media1.skin.local';root=(Join-Path $script:DreamHubHome 'thumbnails')}
  [pscustomobject]@{host='media2.skin.local';root=(Join-Path $script:DreamHubHome 'workshop-thumbnails')}
  [pscustomobject]@{host='media3.skin.local';root=(Join-Path $script:DreamHubHome 'daily-wallpapers')}
  [pscustomobject]@{host='media4.skin.local';root=(Join-Path $script:DreamHubHome 'saved-wallpapers')}
  [pscustomobject]@{host='media5.skin.local';root=(Join-Path $script:DreamHubHome 'wuwa-downloads')}
  [pscustomobject]@{host='media6.skin.local';root=(Join-Path $script:DreamHubHome 'originals')}
  [pscustomobject]@{host='state.skin.local';root=(Join-Path $script:DreamHubState 'themes')}
 )
}
function ConvertTo-DreamHubMediaUrl {
 param([string]$Path)
 Assert-DreamSkinNoReparseComponents $Path
 foreach($mapping in @(Get-AriaMediaMappings)){
  if(Test-DreamSkinThemePathWithin $Path $mapping.root){
   $relative=[IO.Path]::GetFullPath($Path).Substring([IO.Path]::GetFullPath($mapping.root).TrimEnd('\').Length+1)
   $parts=@($relative -split '[\\/]'|ForEach-Object {[Uri]::EscapeDataString($_)})
   return ('https://'+$mapping.host+'/'+($parts -join '/'))
  }
 }
 throw '请使用皮肤媒体目录中的文件。'
}
function Get-DreamHubData {
  $themes=@();$libraryMeta=Get-AriaLibraryMeta
  foreach($entry in @(Get-DreamSkinSavedThemes -SkipImageMetadata)){
    try{
      if($entry.Id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){continue}
      $raw=Read-DreamHubJson (Join-Path $entry.Path 'theme.json') $null;if($raw.archived){continue}
      $stamp=(Get-Item -LiteralPath (Join-Path $entry.Path 'theme.json')).LastWriteTimeUtc.Ticks
      $cached=$script:DreamHubThemeCache[$entry.Id]
      if(-not $cached -or $cached.stamp -ne $stamp){
        $loaded=Read-DreamSkinTheme $entry.Path -SkipImageMetadata
        $item=Get-Item -LiteralPath $loaded.ImagePath
        $kind=if($item.Extension -in @('.mp4','.webm')){'video'}elseif($item.Extension -in @('.gif','.webp')){'gif'}else{'image'}
        $thumbnail=Join-Path (Join-Path $script:DreamHubHome 'thumbnails') ($entry.Id+'.jpg')
        $cached=[pscustomobject]@{stamp=$stamp;id=$entry.Id;name=$entry.Name;url=(ConvertTo-DreamHubMediaUrl $item.FullName);thumbnail=if(Test-Path -LiteralPath $thumbnail){ConvertTo-DreamHubMediaUrl $thumbnail}else{''};kind=$kind;sizeMB=[Math]::Round($item.Length/1MB,2);dimensions='';opacity=$null;sceneProject="$($loaded.Theme.sourceSceneProject)"}
        $script:DreamHubThemeCache[$entry.Id]=$cached
      }
      # A thumbnail may be produced asynchronously after the metadata is cached.
      $thumbnail=Join-Path (Join-Path $script:DreamHubHome 'thumbnails') ($entry.Id+'.jpg');$cached.thumbnail=if(Test-Path -LiteralPath $thumbnail){ConvertTo-DreamHubMediaUrl $thumbnail}else{''}
      $meta=Read-DreamHubJson (Join-Path (Join-Path $script:DreamHubHome 'thumbnails') ($entry.Id+'.json')) $null
      if($meta){$cached.dimensions=[string]$meta.width+' × '+[string]$meta.height;if($cached.kind -ne 'video'){$cached.kind=if($meta.animated){'gif'}else{'image'}}}
      $cached.opacity=Get-DreamSkinLocalOpacity $entry.Id
      $cached|Add-Member -NotePropertyName displayMode -NotePropertyValue (Get-DreamSkinDisplayMode $entry.Id) -Force
      $custom=$libraryMeta.themes.PSObject.Properties[$entry.Id].Value
      $cached.name=if($custom.name){[string]$custom.name}else{$entry.Name}
      $cached|Add-Member -NotePropertyName group -NotePropertyValue ([string]$custom.group) -Force
      $cached|Add-Member -NotePropertyName tags -NotePropertyValue @($custom.tags|Where-Object {$_}) -Force
      $cached|Add-Member -NotePropertyName lastUsed -NotePropertyValue ([string]$custom.lastUsed) -Force
      $cached|Add-Member -NotePropertyName addedAt -NotePropertyValue ((Get-Item -LiteralPath $entry.Path).CreationTimeUtc.ToString('o')) -Force
      $themes+=$cached
    }catch{}
  }
  $active=Read-DreamHubJson (Join-Path $script:DreamHubState 'active-theme\theme.json') $null
  $jobs=@(Get-DreamSceneJobs);$script:AriaRawJobsForNotices=@($jobs)
  # Historical development probes are kept in logs but hidden from the normal task list.
  $hiddenIds=@(Get-AriaHiddenIds);$unlocked=Test-AriaGrant -Role hidden
  $hiddenThemes=@($themes|Where-Object {$_.id -in $hiddenIds})
  $themes=@($themes|Where-Object {$_.id -notin $hiddenIds})
  $jobs=@($jobs|Where-Object {-not $_.testOnly -and $_.status -ne 'completed' -and ($unlocked -or $_.themeId -notin $hiddenIds)})
  foreach($job in $jobs){if($job.status -eq 'waiting-download' -and $job.kind -eq 'workshop'){$job.message=Get-AriaWorkshopDownloadPhase $job.workshopId}}
  $favorites=@(Read-DreamHubJson (Join-Path $script:DreamHubHome 'favorites.json') @())
  if(-not $unlocked){$hiddenThemes=@();$favorites=@($favorites|Where-Object {$_ -notin $hiddenIds})}
  [pscustomobject]@{
    themes=@($themes);hiddenThemes=@($hiddenThemes);hiddenUnlocked=[bool]$unlocked;jobs=@($jobs);heroes=@(Get-DreamHubHeroes)
    prompts=@(Get-DreamHubPrompts);favorites=@($favorites)
    windowSettings=(Read-DreamHubJson (Join-Path $script:DreamHubHome 'window-settings.json') ([pscustomobject]@{remember=$true;width=1370;height=960;state='normal'}))
    activeId="$($active.id)";policy=(Get-DreamHubPolicy);freeGB=[Math]::Round(([IO.DriveInfo]::new('D:\')).AvailableFreeSpace/1GB,1)
  }
}
function Initialize-DreamHubThumbnails {
  $root=Join-Path $script:DreamHubHome 'thumbnails';[void][IO.Directory]::CreateDirectory($root)
  foreach($theme in @(Get-DreamSkinSavedThemes -SkipImageMetadata)){
    try{
      $loaded=Read-DreamSkinTheme $theme.Path -SkipImageMetadata
      if($theme.Id -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){continue}
      $metaPath=Join-Path $root ($theme.Id+'.json')
      $existingMeta=Read-DreamHubJson $metaPath $null
      if(-not $existingMeta -or ([IO.Path]::GetExtension($loaded.ImagePath) -notin @('.mp4','.webm') -and $null -eq $existingMeta.animated)){
        $node=Get-DreamSkinNodeRuntime
        $args=if([IO.Path]::GetExtension($loaded.ImagePath) -in @('.mp4','.webm')){@((Join-Path $PSScriptRoot 'video-metadata.mjs'),$loaded.ImagePath)}else{@((Join-Path $PSScriptRoot 'image-metadata.mjs'),'--check',$loaded.ImagePath)}
        $check=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $args -SeparateStderr
        if($check.ExitCode -eq 0){$meta=($check.Output -join [Environment]::NewLine)|ConvertFrom-Json;Write-DreamHubJson $metaPath $meta}
      }
      $currentMeta=Read-DreamHubJson $metaPath $null
      if([IO.Path]::GetExtension($loaded.ImagePath) -notin @('.mp4','.webm') -and -not $currentMeta.animated){continue}
      $out=Join-Path $root ($theme.Id+'.jpg')
      if(Test-Path -LiteralPath $out){continue}
      $null=Invoke-DreamSkinNative -FilePath (Join-Path $script:DreamSceneTools 'bin\ffmpeg.exe') -ArgumentList @('-hide_banner','-loglevel','error','-nostdin','-y','-i',$loaded.ImagePath,'-frames:v','1','-vf','scale=640:-2','-threads','1',$out) -SeparateStderr
    }catch{}
  }
}


function Move-DreamHubLegacyProfileWhenClosed {
  param([ValidateNotNullOrEmpty()][string]$StateRoot='D:\Aria\runtime')
  # This helper is also called from apply-or-start's child script scope.
  # Never depend on the caller having initialized a script-scoped Hub variable.
  if([IO.Path]::GetFullPath($StateRoot).TrimEnd('\') -ine 'D:\Aria\runtime'){throw '配置迁移路径校验失败。'}
  $legacy=Join-Path $env:USERPROFILE 'AppData\Local\CodexDreamSkin\cdp-profile'
  $target=Join-Path $StateRoot 'cdp-profile'
  if(-not(Test-Path -LiteralPath $legacy -PathType Container)){return}
  $state=Read-DreamHubJson (Join-Path $StateRoot 'state.json') $null
  if($state){
    $install=Get-DreamSkinCodexInstallFromState $state
    if($install -and @(Get-DreamSkinCodexProcesses $install).Count){return}
  }
  if(Test-Path -LiteralPath $target){
    if(@(Get-ChildItem -LiteralPath $target -Force).Count){return}
    [IO.Directory]::Delete($target)
  }
  Assert-DreamSkinNoReparseComponents $legacy;Assert-DreamSkinNoReparseComponents $target
  $expected=Join-Path $env:USERPROFILE 'AppData\Local\CodexDreamSkin\cdp-profile'
  if([IO.Path]::GetFullPath($legacy) -ine [IO.Path]::GetFullPath($expected) -or [IO.Path]::GetFullPath($target) -ine 'D:\Aria\runtime\cdp-profile'){throw '配置迁移路径校验失败。'}
  Move-Item -LiteralPath $legacy -Destination $target -ErrorAction Stop
}

function Remove-DreamHubThemes {
  param([string[]]$Ids)
  $unique=@($Ids|Select-Object -Unique)
  if(-not $unique.Count -or $unique.Count -gt 100){throw '请选择 1 至 100 张皮肤。'}
  $guard=Enter-DreamSkinOperationLock -TimeoutMilliseconds 3000
  try{
    $active=Read-DreamHubJson (Join-Path $script:DreamHubState 'active-theme\theme.json') $null
    $targets=@()
    $roots=@((Join-Path $script:DreamHubHome 'themes'),(Join-Path $script:DreamHubState 'themes'))
    foreach($id in $unique){
      if($id -ceq $active.id){throw '正在使用的皮肤不能卸载，请先换一张背景。'}
      $loaded=Get-DreamHubThemeById $id
      $path=[IO.Path]::GetFullPath($loaded.Directory);$parent=[IO.Path]::GetDirectoryName($path)
      if($parent -notin $roots -or [IO.Path]::GetFileName($path) -cne $id){throw '只能卸载本地皮肤库内的皮肤。'}
      Assert-DreamSkinNoReparseComponents $path
      $targets+=@([pscustomobject]@{Id=$id;Path=$path;Root=$parent;Name=$loaded.Theme.name})
    }
    $removed=@();$failures=@()
    foreach($target in $targets){
      try{Remove-DreamSkinManagedDirectoryVerified -Path $target.Path -Root $target.Root;$removed+=@($target.Id)}catch{$failures+=@($target.Name+'：'+$_.Exception.Message)}
    }
    if($removed.Count){
      $favorites=@(Read-DreamHubJson (Join-Path $script:DreamHubHome 'favorites.json') @()|Where-Object {$_ -notin $removed})
      Write-DreamHubJson (Join-Path $script:DreamHubHome 'favorites.json') @($favorites)
      $prefPath=Join-Path $script:DreamHubState 'theme-preferences.json';$prefs=Read-DreamHubJson $prefPath $null
      foreach($id in $removed){
        if($prefs -and $prefs.themes){$prefs.themes.PSObject.Properties.Remove($id)}
        foreach($ext in @('.jpg','.json')){
          $thumbnail=Join-Path (Join-Path $script:DreamHubHome 'thumbnails') ($id+$ext)
          Assert-DreamSkinNoReparseComponents $thumbnail;if(Test-Path -LiteralPath $thumbnail){[IO.File]::Delete($thumbnail)}
        }
      }
      if($prefs){Write-DreamHubJson $prefPath $prefs}
      $vaultPath=Join-Path $script:AriaPrivacyRoot 'vault.dat'
      if(Test-Path -LiteralPath $vaultPath){$vault=Get-AriaPrivacyConfig;$vault.hiddenIds=@($vault.hiddenIds|Where-Object {$_ -notin $removed});Write-AriaPrivacyConfig $vault}
    }
    return [pscustomobject]@{removedIds=@($removed);failures=@($failures);message=('已卸载 '+$removed.Count+' 张皮肤。原图和 Steam 订阅文件已保留。'+$(if($failures.Count){' 未完成：'+($failures -join '；')}else{''}))}
  }finally{if($guard){Exit-DreamSkinOperationLock $guard}}
}
