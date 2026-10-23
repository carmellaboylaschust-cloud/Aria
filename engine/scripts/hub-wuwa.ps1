. (Join-Path $PSScriptRoot 'hub-wuwa-media.ps1')
$script:WuwaImageCandidates=@{};$script:WuwaImageProbe=$null;$script:WuwaDownloads=[Collections.Generic.List[object]]::new()
$script:WuwaWanted=$false;$script:WuwaStarted=$false;$script:WuwaLoading=$false;$script:WuwaSlowShown=$false;$script:WuwaUrl='https://wuwa.games/';$script:WuwaHealthError=$false
$script:WuwaView=[Microsoft.Web.WebView2.WinForms.WebView2]::new();$script:WuwaView.Visible=$false;$script:WuwaView.ZoomFactor=1
$wuwaProperties=[Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties]::new();$wuwaProperties.UserDataFolder=Join-Path $script:DreamHubHome 'wuwa-profile';$script:WuwaView.CreationProperties=$wuwaProperties
$script:HubForm.Controls.Add($script:WuwaView)
function Test-DreamWuwaUri {
 param([string]$Value)
 try{$u=[Uri]$Value;return $u.IsAbsoluteUri -and $u.Scheme -ceq 'https' -and -not $u.UserInfo -and -not $u.IsLoopback}catch{return $false}
}
function Send-WuwaHealth {
 param([string]$Message,[bool]$Failed=$false)
 $script:WuwaHealthMessage=$Message;$script:WuwaHealthError=$Failed;Send-HubMessage @{type='wuwaHealth';message=$Message;error=$Failed}
}
function Set-DreamWuwaVisible {
 param([bool]$Visible)
 $script:WuwaWanted=$Visible
 if($Visible -and -not $script:WuwaStarted){$script:WuwaStarted=$true;$script:WuwaLoading=$true;$script:WuwaLoadedAt=[DateTime]::UtcNow;Send-WuwaHealth '正在连接呜哇小站，可以随时切换到本地皮肤库。';$null=$script:WuwaView.EnsureCoreWebView2Async($null)}
 $script:WuwaView.Visible=$Visible
 if($script:WuwaView.CoreWebView2){if($Visible){$script:WuwaView.CoreWebView2.Resume()}else{$null=$script:WuwaView.CoreWebView2.TrySuspendAsync()}}
}
function Set-DreamWuwaBounds {
 param($Request)
 if($Request.viewportWidth -le 0 -or $Request.viewportHeight -le 0){return}
 $sx=$script:HubView.ClientSize.Width/[double]$Request.viewportWidth;$sy=$script:HubView.ClientSize.Height/[double]$Request.viewportHeight
 $x=[Math]::Max(0,[int]($Request.x*$sx));$y=[Math]::Max(0,[int]($Request.y*$sy))
 $w=[Math]::Max(1,[Math]::Min([int]($Request.width*$sx),$script:HubForm.ClientSize.Width-$x));$h=[Math]::Max(1,[Math]::Min([int]($Request.height*$sy),$script:HubForm.ClientSize.Height-$y))
 $script:WuwaView.Bounds=[Drawing.Rectangle]::new($x,$y,$w,$h);$script:WuwaView.BringToFront()
}
function Update-DreamWuwaHealth {
 Update-AriaWuwaImages
 if($script:WuwaLoading -and -not $script:WuwaSlowShown -and ([DateTime]::UtcNow-$script:WuwaLoadedAt).TotalSeconds -ge 15){$script:WuwaSlowShown=$true;Send-WuwaHealth '小站响应较慢。可刷新重试，或先浏览我的皮肤。' $true}
}
$script:WuwaView.add_CoreWebView2InitializationCompleted({
 param($sender,$eventArgs)
 if(-not $eventArgs.IsSuccess){$script:WuwaLoading=$false;Send-WuwaHealth '网页组件暂未启动，可刷新重试或用浏览器打开。' $true;return}
 $core=$script:WuwaView.CoreWebView2
 $core.Settings.IsWebMessageEnabled=$false;$core.Settings.AreHostObjectsAllowed=$false;$core.Settings.AreDevToolsEnabled=$false;$core.Settings.IsStatusBarEnabled=$false;$core.Settings.AreDefaultScriptDialogsEnabled=$false
 # The remote site has its own profile and no local directory mappings or app bridge.
 $downloads=Join-Path $script:DreamHubHome 'wuwa-downloads';Assert-DreamSkinNoReparseComponents $downloads;[void][IO.Directory]::CreateDirectory($downloads);$core.Profile.DefaultDownloadFolderPath=$downloads
 $core.add_NavigationStarting({
  param($sender,$eventArgs)
  if(-not(Test-DreamWuwaUri $eventArgs.Uri)){$eventArgs.Cancel=$true;Send-WuwaHealth '此链接无法在专区打开。普通网页请使用 HTTPS 地址。' $true;return}
  $script:WuwaUrl=$eventArgs.Uri;$script:WuwaLoading=$true;$script:WuwaSlowShown=$false;$script:WuwaLoadedAt=[DateTime]::UtcNow
  Send-HubMessage @{type='wuwaUrl';url=$script:WuwaUrl};Send-WuwaHealth '正在加载呜哇小站，可随时切换到本地页面。'
 })
 $core.add_NavigationCompleted({param($sender,$eventArgs) $script:WuwaLoading=$false;if($eventArgs.IsSuccess){Send-WuwaHealth '呜哇小站 · 已连接'}else{Send-WuwaHealth '连接暂未完成，请刷新或用浏览器打开。' $true}})
 $core.add_NewWindowRequested({param($sender,$eventArgs) $eventArgs.Handled=$true;if(Test-DreamWuwaUri $eventArgs.Uri){$script:WuwaView.CoreWebView2.Navigate($eventArgs.Uri)}else{Send-WuwaHealth '此链接无法在专区打开。' $true}})
 $core.add_PermissionRequested({param($sender,$eventArgs) $eventArgs.State=[Microsoft.Web.WebView2.Core.CoreWebView2PermissionState]::Deny})
 $core.add_DownloadStarting({
  param($sender,$eventArgs)
  $operation=$eventArgs.DownloadOperation
  $ext=switch(($operation.MimeType -split ';')[0].ToLowerInvariant()){'image/jpeg'{'.jpg'}'image/png'{'.png'}'image/webp'{'.webp'}'image/gif'{'.gif'}default{''}}
  if(-not $ext -or $operation.TotalBytesToReceive -gt 32MB -or $script:WuwaDownloads.Count -ge 10){$eventArgs.Cancel=$true;Send-WuwaHealth '这里只接收 32 MB 以内的 JPG、PNG、WebP 和 GIF 图片。' $true;return}
  $name=[IO.Path]::GetFileNameWithoutExtension($eventArgs.ResultFilePath);if(-not $name){$name='鸣潮壁纸'};if($name.Length -gt 70){$name=$name.Substring(0,70)}
  $path=Join-Path 'D:\Aria\user-backgrounds\wuwa-downloads' ('wuwa-'+[guid]::NewGuid().ToString('N')+$ext)
  Assert-DreamSkinNoReparseComponents $path;$eventArgs.ResultFilePath=$path;$eventArgs.Handled=$true
  $script:WuwaDownloads.Add([pscustomobject]@{Operation=$operation;Path=$path;Title=$name;Page=$script:WuwaUrl})
  Send-WuwaHealth '正在下载到 D 盘；检查通过后会自动加入我的皮肤。'
 })
 $core.Navigate($script:WuwaUrl)
})

function Start-AriaWuwaImagePicker {
 param([int]$RequestId)
 if(-not $script:WuwaView.CoreWebView2 -or $script:WuwaLoading){throw '请等网页加载完成后，再读取本页图片。'}
 if($script:WuwaImageProbe){throw '正在读取本页图片，请稍等片刻。'}
 $script:WuwaView.Visible=$false;$script:WuwaImageCandidates=@{}
 $query=Get-Content -LiteralPath (Join-Path $script:HubCodeRoot 'assets\wuwa-page-images.js') -Raw -Encoding UTF8
 $script:WuwaImageProbe=[pscustomobject]@{Task=$script:WuwaView.CoreWebView2.ExecuteScriptAsync($query);RequestId=$RequestId;Page=$script:WuwaUrl;Deadline=[DateTime]::UtcNow.AddSeconds(20)}
}
function Update-AriaWuwaImages {
 if($script:WuwaImageProbe){
  $probe=$script:WuwaImageProbe
  if($probe.Task.IsCompleted -or [DateTime]::UtcNow -gt $probe.Deadline){
   $script:WuwaImageProbe=$null
   try{
    if(-not $probe.Task.IsCompleted){throw '读取网页图片超时，请刷新后重试。'}
    if($probe.Task.IsFaulted -or $probe.Task.IsCanceled){throw '网页图片暂未读取成功，请重试。'}
    if($probe.Page -cne $script:WuwaUrl){throw '网页已跳转，请重新读取本页图片。'}
    $data=$probe.Task.Result|ConvertFrom-Json;$items=@()
    foreach($image in @($data.images|Select-Object -First 40)){
     if(-not(Test-AriaPublicMediaUri ([string]$image.url))){continue}
     $id=[guid]::NewGuid().ToString('N');$preview=if(Test-AriaPublicMediaUri ([string]$image.preview)){$image.preview}else{$image.url}
     $title=([string]$image.title);if($title.Length -gt 70){$title=$title.Substring(0,70)}
     $script:WuwaImageCandidates[$id]=[pscustomobject]@{url=[string]$image.url;title=$title;sourcePage=$probe.Page;expires=[DateTime]::UtcNow.AddMinutes(30)}
     $items+=@([pscustomobject]@{id=$id;preview=[string]$preview;title=$title;width=[int]$image.width;height=[int]$image.height})
    }
    Send-HubMessage @{id=$probe.RequestId;ok=$true;images=@($items)}
   }catch{Send-HubMessage @{id=$probe.RequestId;ok=$false;error=$_.Exception.Message}}
  }
 }
 foreach($download in @($script:WuwaDownloads.ToArray())){
  try{
   if($download.Operation.BytesReceived -gt 32MB){$download.Operation.Cancel();Send-HubMessage @{type='notice';message='网页图片超过 32 MB，已停止下载。'};[void]$script:WuwaDownloads.Remove($download);continue}
   $status=[string]$download.Operation.State
   if($status -eq 'Completed'){
    Start-HubAction ([pscustomobject]@{id=0;action='importWuwaDownload';path=$download.Path;title=$download.Title;sourcePage=$download.Page})
    [void]$script:WuwaDownloads.Remove($download)
   }elseif($status -eq 'Interrupted'){Send-HubMessage @{type='notice';message='网页图片下载未完成，可以在原页面重新下载。'};[void]$script:WuwaDownloads.Remove($download)}
  }catch{[void]$script:WuwaDownloads.Remove($download);Send-HubMessage @{type='notice';message='图片下载状态暂未读取成功，请在原页面重试。'}}
 }
}
