
param([switch]$TestMode)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'background-library.ps1')
. (Join-Path $PSScriptRoot 'scene-queue.ps1')
. (Join-Path $PSScriptRoot 'hub-workshop.ps1')
. (Join-Path $PSScriptRoot 'hub-data.ps1')
. (Join-Path $PSScriptRoot 'hub-feed.ps1')
. (Join-Path $PSScriptRoot 'hub-window.ps1')

$script:HubInstance=[Threading.Mutex]::new($false,('Local\Aria.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value+'.Hub'))
try{$script:OwnHubInstance=$script:HubInstance.WaitOne(0)}catch [Threading.AbandonedMutexException]{$script:OwnHubInstance=$true}
if(-not $script:OwnHubInstance){
  try{
    $existing=Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'"|Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -like '*skin-hub.ps1*'}
    foreach($process in $existing){
      $handle=Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
      if($handle.MainWindowTitle -eq 'Aria'){
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class DreamHubFocus{[DllImport("user32.dll")]static extern bool ShowWindow(IntPtr h,int n);[DllImport("user32.dll")]static extern bool SetForegroundWindow(IntPtr h);[DllImport("user32.dll")]static extern bool IsIconic(IntPtr h);public static void Activate(IntPtr h){if(IsIconic(h))ShowWindow(h,9);SetForegroundWindow(h);}}'
        [DreamHubFocus]::Activate($handle.MainWindowHandle);break
      }
    }
  }catch{}
  $script:HubInstance.Dispose();exit 0
}

Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$script:HubCodeRoot=Split-Path $PSScriptRoot
$script:HubLog=Join-Path $script:DreamHubHome 'hub.log'
$taskTemp='D:\Aria\user-backgrounds\temp';[void][IO.Directory]::CreateDirectory($taskTemp);$env:TEMP=$taskTemp;$env:TMP=$taskTemp
$script:HubRequests=Join-Path $script:DreamHubHome 'requests'
[void][IO.Directory]::CreateDirectory($script:HubRequests)
function Write-HubLog {param($Value) [IO.File]::AppendAllText($script:HubLog,([DateTime]::Now.ToString('s')+' '+$Value+[Environment]::NewLine),[Text.Encoding]::UTF8)}
. (Join-Path $PSScriptRoot 'hub-display.ps1')
[DreamHubDisplay]::Initialize()
. (Join-Path $PSScriptRoot 'hub-brand.ps1')
Initialize-DreamAriaBrand -AppId 'Aria.SkinStudio'
$tools='D:\Aria\tools\webview2'
$env:PATH=$tools+';'+$env:PATH
Add-Type -Path (Join-Path $tools 'Microsoft.Web.WebView2.Core.dll')
Add-Type -Path (Join-Path $tools 'Microsoft.Web.WebView2.WinForms.dll')
[Windows.Forms.Application]::EnableVisualStyles()
$script:HubPending=[Collections.Generic.List[object]]::new()
$script:HubReady=$false;$script:SteamWanted=$false;$script:SteamStarted=$false;$script:SteamLoading=$false;$script:SteamSlowShown=$false
$script:SteamUrl='https://steamcommunity.com/app/431960/workshop/?l=schinese'
$script:LastData='';$script:NextData=[DateTime]::MinValue;$script:LaunchInFlight=$false;$script:LastThumbCheck=[DateTime]::MinValue
$script:HubForm=[DreamHubWindow]::new()
$script:HubForm.Text='Aria'
$script:HubForm.StartPosition='CenterScreen'
$script:HubForm.Size=[Drawing.Size]::new(1370,960)
$script:HubForm.MinimumSize=[Drawing.Size]::new(1060,760)
$script:HubForm.FitInitialDisplay()
Restore-DreamHubWindowSettings
$script:HubForm.BackColor=[Drawing.ColorTranslator]::FromHtml('#F7FAFC')
try{$script:HubForm.Icon=[Drawing.Icon]::new((Join-Path $script:DreamHubHome 'aria.ico'))}catch{}
Set-DreamAriaWindowBrand -Handle $script:HubForm.Handle
$script:HubForm.add_HandleCreated({Set-DreamAriaWindowBrand -Handle $script:HubForm.Handle})
$script:HubView=[Microsoft.Web.WebView2.WinForms.WebView2]::new()
$script:HubView.ZoomFactor=1.0
$script:HubView.Dock='Fill';$script:HubView.DefaultBackgroundColor=$script:HubForm.BackColor
$properties=[Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties]::new()
$properties.UserDataFolder=Join-Path $script:DreamHubHome 'browser-profile'
$script:HubView.CreationProperties=$properties
$script:HubForm.Controls.Add($script:HubView)
$script:SteamView=[Microsoft.Web.WebView2.WinForms.WebView2]::new()
$script:SteamView.ZoomFactor=1.0
$script:SteamView.Visible=$false
$steamProperties=[Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties]::new()
$steamProperties.UserDataFolder=Join-Path $script:DreamHubHome 'steam-profile'
$script:SteamView.CreationProperties=$steamProperties
$script:HubForm.Controls.Add($script:SteamView)
function Send-HubMessage {
  param($Message)
  if($script:HubReady -and $script:HubView.CoreWebView2 -and ([Uri]$script:HubView.CoreWebView2.Source).Host -ceq 'app.skin.local'){
    $script:HubView.CoreWebView2.PostWebMessageAsJson(($Message|ConvertTo-Json -Depth 14 -Compress))
  }
}
function Send-SteamHealth {param([string]$Message,[bool]$Failed=$false) $script:SteamHealthMessage=$Message;$script:SteamHealthError=$Failed;Send-HubMessage @{type='steamHealth';message=$Message;error=$Failed}}
function Test-SteamUri {
  param([string]$Value)
  try{$uri=[Uri]$Value;return $uri.IsAbsoluteUri -and $uri.Scheme -ceq 'https' -and $uri.Host -in @('steamcommunity.com','store.steampowered.com','help.steampowered.com','login.steampowered.com')}catch{return $false}
}
function Get-AriaLaunchWorker {
 if($script:AriaLaunchWorker -and -not $script:AriaLaunchWorker.HasExited){return $script:AriaLaunchWorker}
 if($script:AriaLaunchWorker){$script:AriaLaunchWorker.Dispose()}
 $script:AriaLaunchQueueToken=[guid]::NewGuid().ToString('N')
 $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
 $info.Arguments=ConvertTo-DreamSkinArgumentLine @('-NoProfile','-STA','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $PSScriptRoot 'hub-actions.ps1'),'-Worker','-OwnerPid',"$PID",'-OwnerStarted',(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'),'-QueueToken',$script:AriaLaunchQueueToken)
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
 $script:AriaLaunchWorker=[Diagnostics.Process]::Start($info)
 return $script:AriaLaunchWorker
}
function Start-HubAction {
 param($Request)
 $key=[guid]::NewGuid().ToString('N');$persistent=$Request.action -eq 'launch'
 if($persistent){$process=Get-AriaLaunchWorker;$key+='.'+$script:AriaLaunchQueueToken+'.launch'}
 $inputFile=Join-Path $script:HubRequests ($key+'.request.json')
 $outputFile=Join-Path $script:HubRequests ($key+'.result.json')
 if($Request.action -in @('exportBackup','inspectBackup','restoreBackup')){$Request|Add-Member -NotePropertyName ariaAdminAccess -NotePropertyValue $script:AriaAdminToken -Force}
 $Request|Add-Member -NotePropertyName ariaHiddenAccess -NotePropertyValue $script:AriaHiddenToken -Force
 # Atomically publish a complete request before the warm worker can claim it.
 Write-DreamHubJson $inputFile $Request
 if(-not $persistent){
  $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
  $info.Arguments=ConvertTo-DreamSkinArgumentLine @('-NoProfile','-STA','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $PSScriptRoot 'hub-actions.ps1'),'-RequestPath',$inputFile,'-ResultPath',$outputFile)
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
  $process=[Diagnostics.Process]::Start($info)
 }
 $script:HubPending.Add([pscustomobject]@{Process=$process;Persistent=$persistent;InputPath=$inputFile;Path=$outputFile;Action=$Request.action;Id=$Request.id;Started=[DateTime]::UtcNow})
}

function Open-HubExternal {
  param([string]$Uri)
  $info=[Diagnostics.ProcessStartInfo]::new($Uri);$info.UseShellExecute=$true
  $process=[Diagnostics.Process]::Start($info);if($process){$process.Dispose()}
}
function Show-DownloadedWallpapers {
  $items=@()
  foreach($root in Get-DreamHubWorkshopRoots){foreach($folder in Get-ChildItem -LiteralPath $root -Directory){
    $path=Join-Path $folder.FullName 'project.json'
    if(Test-Path -LiteralPath $path){try{$data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;if($data.type -in @('scene','video')){$items+=[pscustomobject]@{Id=$folder.Name;Name="$($data.title)";Type="$($data.type)"}}}catch{}}
  }}
  if(-not $items.Count){throw '暂未找到已下载的 Scene 或视频壁纸，请先在 Steam 中订阅下载。'}
  $dialog=[Windows.Forms.Form]::new();$dialog.Text='已下载的 Wallpaper Engine 壁纸';$dialog.Size=[Drawing.Size]::new(650,450);$dialog.StartPosition='CenterParent';$dialog.Icon=$script:HubForm.Icon
  $list=[Windows.Forms.ListBox]::new();$list.Dock='Fill';$list.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
  foreach($item in $items){[void]$list.Items.Add($item.Name+' · '+$item.Type+' · '+$item.Id)}
  $button=[Windows.Forms.Button]::new();$button.Dock='Bottom';$button.Height=44;$button.Text='加入自动导入任务';$button.DialogResult='OK'
  $dialog.Controls.Add($list);$dialog.Controls.Add($button);$list.SelectedIndex=0
  $script:SteamView.Visible=$false
  try{if($dialog.ShowDialog($script:HubForm) -eq 'OK' -and $list.SelectedIndex -ge 0){$id=$items[$list.SelectedIndex].Id;Start-HubAction ([pscustomobject]@{id=0;action='workshopImport';workshopId=$id})}}
  finally{$dialog.Dispose();$script:SteamView.Visible=$script:SteamWanted;$script:WuwaView.Visible=$script:WuwaWanted}
}
. (Join-Path $PSScriptRoot 'hub-wuwa.ps1')
. (Join-Path $PSScriptRoot 'hub-steam-subscription.ps1')
. (Join-Path $PSScriptRoot 'hub-connection.ps1')
. (Join-Path $PSScriptRoot 'hub-privacy-extra.ps1')
. (Join-Path $PSScriptRoot 'hub-backup.ps1')
. (Join-Path $PSScriptRoot 'hub-job-notices.ps1')
function Invoke-HubMessage {
  param($Request)
  $answer=[ordered]@{id=$Request.id;ok=$true}
  $background=$false
  switch($Request.action){
    'ready' {Start-DreamHubDailyWorker;$script:HubReady=$true;$null=Get-AriaLaunchWorker;$script:LastData='';if((Get-DreamHubPolicy).autoImportWorkshop -or @(Get-DreamSceneJobs|Where-Object {$_.status -in @('queued','waiting-download')}).Count){Start-DreamSceneWorker};$script:NextData=[DateTime]::MinValue;Start-HubAction ([pscustomobject]@{id=0;action='prepare'})}
    'workshop' {
      $script:SteamWanted=[bool]$Request.visible
      if($script:SteamWanted -and -not $script:SteamStarted){
        $script:SteamStarted=$true;Send-SteamHealth '正在连接 Steam，可随时切换到本地皮肤库。'
        $script:SteamLoading=$true;$script:SteamLoadingAt=[DateTime]::UtcNow;$script:SteamSlowShown=$false
        $null=$script:SteamView.EnsureCoreWebView2Async($null)
      }
      $script:SteamView.Visible=$script:SteamWanted
      if($script:SteamView.CoreWebView2){if($script:SteamWanted){$script:SteamView.CoreWebView2.Resume()}else{$null=$script:SteamView.CoreWebView2.TrySuspendAsync()}}
    }
    'steamBounds' {
      if($Request.viewportWidth -gt 0 -and $Request.viewportHeight -gt 0){
        $sx=$script:HubView.ClientSize.Width/[double]$Request.viewportWidth;$sy=$script:HubView.ClientSize.Height/[double]$Request.viewportHeight
        $x=[Math]::Max(0,[int]($Request.x*$sx));$y=[Math]::Max(0,[int]($Request.y*$sy))
        $w=[Math]::Max(1,[Math]::Min([int]($Request.width*$sx),$script:HubForm.ClientSize.Width-$x))
        $h=[Math]::Max(1,[Math]::Min([int]($Request.height*$sy),$script:HubForm.ClientSize.Height-$y))
        $script:SteamView.Bounds=[Drawing.Rectangle]::new($x,$y,$w,$h);$script:SteamView.BringToFront()
      }
    }
    'steamGo' {
      $value="$($Request.url)".Trim()
      if($value -match '^\d{6,12}$'){$value='https://steamcommunity.com/sharedfiles/filedetails/?id='+$value+'&l=schinese'}
      if(-not(Test-SteamUri $value)){throw '请输入 Steam 创意工坊链接或壁纸编号。'}
      $script:SteamUrl=$value;if($script:SteamView.CoreWebView2){$script:SteamView.CoreWebView2.Navigate($value)}
    }
    'steamBack' {if($script:SteamView.CoreWebView2 -and $script:SteamView.CoreWebView2.CanGoBack){$script:SteamView.CoreWebView2.GoBack()}}
    'steamHome' {$script:SteamView.CoreWebView2.Navigate('https://steamcommunity.com/app/431960/workshop/?l=schinese')}
    'steamReload' {if($script:SteamView.CoreWebView2){$script:SteamView.CoreWebView2.Reload()}else{throw 'Steam 组件仍在初始化，请稍等片刻。'}}
    'steamExternal' {Open-HubExternal $script:SteamUrl}
    'browseDownloaded' {$script:SteamView.Visible=$false;$script:WuwaView.Visible=$false;Start-HubAction $Request;$background=$true}
    'wuwaImages' {Start-AriaWuwaImagePicker -RequestId ([int]$Request.id);$background=$true}
    'wuwaSaveImage' {
      $item=$script:WuwaImageCandidates[[string]$Request.imageId]
      if(-not $item -or [DateTime]::UtcNow -gt $item.expires){throw '图片选择已过期，请重新读取本页图片。'}
      Start-HubAction ([pscustomobject]@{id=$Request.id;action='saveWuwaImage';url=$item.url;title=$item.title;sourcePage=$item.sourcePage});$background=$true
    }
    'wuwaImagePickerClose' {$script:WuwaView.Visible=$script:WuwaWanted}
    'downloadedClose' {$script:SteamView.Visible=$script:SteamWanted;$script:WuwaView.Visible=$script:WuwaWanted}
    'importWorkshop' {
      Start-DreamSteamSubscribeAndImport
      $answer.message='正在确认订阅，下载完成后自动导入';$answer.subscriptionPending=$true
    }

    'privacyStatus' {$answer.initialized=Test-AriaPrivacyInitialized}
    'privacySetup' {Initialize-AriaPrivacy -Password ([string]$Request.password) -Confirmation ([string]$Request.confirmation) -Questions @($Request.questions);$answer.message='管理员已设置，请使用新密码验证。';$script:NextData=[DateTime]::MinValue}
    'privacyChallenge' {$challenge=New-AriaPrivacyChallenge;$answer.challengeId=$challenge.challengeId;$answer.question=$challenge.question;$script:NextData=[DateTime]::MinValue}
    'privacyAnswer' {Unlock-AriaHidden -ChallengeId ([string]$Request.challengeId) -Answer ([string]$Request.answer);$answer.hiddenUnlocked=$true;$script:NextData=[DateTime]::MinValue}
    'privacyLock' {Lock-AriaHidden;$answer.hiddenUnlocked=$false;$script:NextData=[DateTime]::MinValue;Send-HubMessage @{type='privacyLocked'}}
    'privacyAdminLogin' {Unlock-AriaAdmin ([string]$Request.password);$answer.questions=@(Get-AriaQuestionBank)}
    {$_ -in @('backupExport','backupInspect','backupPrivateExport','backupPrivateInspect')} {
      $private=$Request.action -like 'backupPrivate*';$save=$Request.action -in @('backupExport','backupPrivateExport');$secret=''
      if($private){
        Assert-AriaPrivateBackupAccess $script:AriaAdminToken
        $password=[string]$Request.password
        if($password.Length -gt 128 -or -not $password -or ($save -and ($password.Trim().Length -lt 8 -or $password -cne [string]$Request.confirmation))){throw '请填写正确的备份密码；新备份至少 8 字，两次输入需一致。'}
        $secret=[AriaPrivacyCrypto]::Protect($password);$password=''
      }
      $path=Show-AriaBackupFileDialog -Private:$private -Save:$save
      if($path){Start-HubAction ([pscustomobject]@{id=$Request.id;action=$(if($save){'exportBackup'}else{'inspectBackup'});path=$path;scope=$(if($private){'private'}else{'public'});protectedPassword=$secret});$background=$true}else{$answer.cancelled=$true}
    }
    'backupRestore' {
      if([string]$Request.planId -cnotmatch '^[a-f0-9]{32}$'){throw '恢复预览编号无效。'}
      $plan=Read-DreamHubJson (Join-Path (Join-Path (Get-AriaBackupRoot) 'plans') ($Request.planId+'.json')) $null
      if($plan.scope -eq 'private'){Assert-AriaPrivateBackupAccess $script:AriaAdminToken}
      Start-HubAction ([pscustomobject]@{id=$Request.id;action='restoreBackup';planId=[string]$Request.planId;applySettings=[bool]$Request.applySettings});$background=$true
    }
    {$_ -in @('storageOverview','storageCleanup')} {Start-HubAction $Request;$background=$true}
    'openBackups' {Open-HubExternal (Get-AriaBackupRoot)}
    'savePlaybackSettings' {Save-AriaPlaybackSettings -Mode ([string]$Request.mode);$script:NextData=[DateTime]::MinValue;$answer.message='播放策略已保存，当前背景会自动更新，无需重启'}
    'privacyMode' {$answer.message=Invoke-AriaPrivacyMode}
    'savePrivacySettings' {Save-AriaPrivacySettings -ThemeId ([string]$Request.themeId);$script:NextData=[DateTime]::MinValue;$answer.message='隐私模式背景已保存'}
    'privacyChangePassword' {Change-AriaAdminPassword -CurrentPassword ([string]$Request.currentPassword) -NewPassword ([string]$Request.newPassword) -Confirmation ([string]$Request.confirmation);Send-HubMessage @{type='privacyLocked'};$script:NextData=[DateTime]::MinValue;$answer.message='管理员密码已更新，隐藏列表和管理员权限已锁定，请重新验证。'}
    'privacyAdminLock' {Lock-AriaAdmin}
    'privacySaveQuestions' {Save-AriaQuestionBank @($Request.questions);$answer.questions=@(Get-AriaQuestionBank);$answer.message='问题库已保存'}
    'hideThemes' {Set-AriaThemesHidden -Ids @($Request.themeIds) -Hidden ([bool]$Request.hidden);$answer.changedIds=@($Request.themeIds);$answer.hidden=[bool]$Request.hidden;$answer.message=if($Request.hidden){'已移入隐藏皮肤'}else{'已移回普通皮肤列表'};$script:NextData=[DateTime]::MinValue}
    'clearCancelledJobs' {$count=Remove-AriaCancelledJobs -Ids @($Request.jobIds) -All:([bool]$Request.all);$answer.message='已清除 '+$count+' 个已取消任务';$answer.cleared=$count;$script:NextData=[DateTime]::MinValue}
    'launchDesktop' {
      $result=Start-AriaDesktopFromHub
      $answer.waitingForExit=[bool]$result.waitingForExit;$answer.message=$result.message
    }
    'connectAfterExit' {$script:AriaConnectPending=[DateTime]::UtcNow.AddMinutes(10);$script:AriaConnectionDue=[DateTime]::MinValue;$script:NextData=[DateTime]::MinValue;$answer.message='已开始等待。请保存工作并自行退出桌面端，Aria 会接续带背景启动。'}
    'cancelConnect' {$script:AriaConnectPending=$null;$script:AriaConnectionDue=[DateTime]::MinValue;$script:NextData=[DateTime]::MinValue;$answer.message='已取消连接等待'}
    'favorite' {
      $null=Get-DreamHubThemeById $Request.themeId
      $path=Join-Path $script:DreamHubHome 'favorites.json';$favorites=@(Read-DreamHubJson $path @())
      if($favorites -contains $Request.themeId){$favorites=@($favorites|Where-Object {$_ -cne $Request.themeId})}else{$favorites+=@("$($Request.themeId)")}
      Write-DreamHubJson $path @($favorites);$script:NextData=[DateTime]::MinValue
    }
    'windowPreset' {Set-DreamHubWindowPreset $Request.preset;$answer.message='窗口大小已调整，也可以拖动边框微调'}
    'windowRemember' {$settings=Get-DreamHubWindowSettings;$settings.remember=[bool]$Request.value;Write-DreamHubJson (Join-Path $script:DreamHubHome 'window-settings.json') $settings;Save-DreamHubWindowSettings;$answer.message='窗口偏好已保存'}
    'displayMode' {$null=Get-DreamHubThemeById $Request.themeId;Set-DreamSkinDisplayMode -ThemeId $Request.themeId -Mode $Request.mode;$script:NextData=[DateTime]::MinValue;$answer.message='背景显示方式已保存，正在使用的背景会自动更新'}
    'opacity' {$null=Get-DreamHubThemeById $Request.themeId;Set-DreamSkinLocalOpacity -ThemeId $Request.themeId -Opacity $Request.value;$script:NextData=[DateTime]::MinValue}
    'copy' {if("$($Request.text)".Length -gt 16000){throw '内容过长。'};[Windows.Forms.Clipboard]::SetText("$($Request.text)");$answer.message='已复制这次的提示词'}
    'savePrompt' {
      $name="$($Request.name)".Trim();$text="$($Request.text)".Trim()
      if(-not $name -or -not $text -or $name.Length -gt 80 -or $text.Length -gt 10000){throw '请填写名称和提示词，提示词最多 10000 字。'}
      $path=Join-Path $script:DreamHubHome 'prompts.json';$prompts=@(Read-DreamHubJson $path @());$id="$($Request.promptId)"
      if($id -cnotmatch '^prompt-[a-f0-9]{32}$'){$id='prompt-'+[guid]::NewGuid().ToString('N')}
      $category=[string]$Request.category;if($category -notin @('学习','写作','编程','规划','创作','自定义')){$category='自定义'}
      $sceneThemeId=[string]$Request.sceneThemeId;if($sceneThemeId){$null=Get-DreamHubThemeById $sceneThemeId}
      if($null -ne $Request.sceneOpacity -and ([int]$Request.sceneOpacity -lt 0 -or [int]$Request.sceneOpacity -gt 100)){throw '场景不透明度范围为 0–100。'}
      $tone=[string]$Request.tone;$format=[string]$Request.format;$detail=[string]$Request.detail
      if($tone -notin @('','清楚简洁','温柔耐心','正式严谨','轻松自然') -or $format -notin @('','分步说明','提纲与清单','对比表格','完整文章') -or $detail -notin @('','简短重点','适中详细','充分展开')){throw '提示词偏好无效。'}
      $prompts=@($prompts|Where-Object {$_.id -cne $id})+@([pscustomobject]@{id=$id;name=$name;text=$text;builtin=$false;category=$category;tone=$tone;format=$format;detail=$detail;sceneThemeId=$sceneThemeId;sceneOpacity=$Request.sceneOpacity})
      Write-DreamHubJson $path @($prompts);$answer.promptId=$id;$answer.message='已保存到提示词小屋';$script:NextData=[DateTime]::MinValue
    }
    'deletePrompt' {
      if("$($Request.promptId)" -cnotmatch '^prompt-[a-f0-9]{32}$'){throw '只能移除自定义提示词。'}
      $path=Join-Path $script:DreamHubHome 'prompts.json';$prompts=@(Read-DreamHubJson $path @()|Where-Object {$_.id -cne $Request.promptId});Write-DreamHubJson $path @($prompts);$script:NextData=[DateTime]::MinValue;$answer.message='已移除自定义提示词'
    }
    'savePolicy' {
      if([int]$Request.videoMaxMB -notin @(64,128,256) -or [int]$Request.sceneMaxMB -notin @(128,256,512)){throw '导入规则无效。'}
      $policy=Get-DreamHubPolicy;$policy.videoMaxMB=[int]$Request.videoMaxMB;$policy.sceneMaxMB=[int]$Request.sceneMaxMB;$policy.autoImportWorkshop=[bool]$Request.autoImportWorkshop
      Write-DreamHubJson (Join-Path $script:DreamHubHome 'import-policy.json') $policy;$answer.message='导入规则已保存';$script:NextData=[DateTime]::MinValue
    }
    'openSavedWallpapers' {$saved=Join-Path $script:DreamHubHome 'saved-wallpapers';[void][IO.Directory]::CreateDirectory($saved);Open-HubExternal $saved}
    'openStorage' {Open-HubExternal $script:DreamHubHome}
    'wuwa' {Set-DreamWuwaVisible ([bool]$Request.visible)}
    'wuwaBounds' {Set-DreamWuwaBounds $Request}
    'wuwaBack' {if($script:WuwaView.CoreWebView2 -and $script:WuwaView.CoreWebView2.CanGoBack){$script:WuwaView.CoreWebView2.GoBack()}}
    'wuwaHome' {if($script:WuwaView.CoreWebView2){$script:WuwaView.CoreWebView2.Navigate('https://wuwa.games/')}}
    'wuwaReload' {if($script:WuwaView.CoreWebView2){$script:WuwaView.CoreWebView2.Reload()}else{throw '网页仍在初始化，请稍等片刻。'}}
    'wuwaExternal' {Open-HubExternal $script:WuwaUrl}
    'openSource' {if($Request.site -eq 'wuwa'){Open-HubExternal 'https://wuwa.games/'}elseif($Request.site -eq 'emoji'){Open-HubExternal 'https://emoji.wuwa.games/'}}
    'addMedia' {
      $dialog=[Windows.Forms.OpenFileDialog]::new();$dialog.Title='添加本地背景';$dialog.Filter='背景素材|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.mp4;*.webm';$dialog.Multiselect=$true
      $script:SteamView.Visible=$false;$script:WuwaView.Visible=$false
      try{if($dialog.ShowDialog($script:HubForm) -eq 'OK'){Start-HubAction ([pscustomobject]@{id=$Request.id;action='addMedia';paths=@($dialog.FileNames)});$background=$true}}finally{$dialog.Dispose();$script:SteamView.Visible=$script:SteamWanted;$script:WuwaView.Visible=$script:WuwaWanted}
    }
    'addScene' {
      $dialog=[Windows.Forms.OpenFileDialog]::new();$dialog.Title='选择 Wallpaper Engine Scene / Web 项目';$dialog.Filter='项目说明|project.json';$dialog.InitialDirectory='D:\'
      try{if($dialog.ShowDialog($script:HubForm) -eq 'OK'){Start-HubAction ([pscustomobject]@{id=$Request.id;action='addScene';path=$dialog.FileName;seconds=$Request.seconds});$background=$true}}finally{$dialog.Dispose()}
    }
    'launch' {
      if($script:LaunchInFlight){throw '桌面端正在启动，请稍等。'}
      $null=Get-DreamHubThemeById $Request.themeId;$script:LaunchInFlight=$true
      Start-HubAction $Request;Send-HubMessage @{type='launchProgress';message='正在准备皮肤与桌面端，可以继续浏览。'}
    }
    {$_ -in @('record','importHero','cancelJob','retryJob','uninstallThemes','workshopBatch','saveLibraryMeta')} {Start-HubAction $Request;$background=$true}
    default {throw '未知操作。'}
  }
  if(-not $background){Send-HubMessage $answer}
}
$script:HubView.add_CoreWebView2InitializationCompleted({
  param($sender,$eventArgs)
  if(-not $eventArgs.IsSuccess){Write-HubLog $eventArgs.InitializationException;[void][Windows.Forms.MessageBox]::Show('界面组件启动失败，请重新打开。','Aria');return}
  $core=$script:HubView.CoreWebView2
  $core.Settings.AreHostObjectsAllowed=$false;$core.Settings.AreDevToolsEnabled=$false;$core.Settings.AreDefaultContextMenusEnabled=$false
  $core.SetVirtualHostNameToFolderMapping('app.skin.local',(Join-Path $script:HubCodeRoot 'hub'),[Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::DenyCors)
  foreach($mapping in @(Get-AriaMediaMappings)){
   Assert-DreamSkinNoReparseComponents $mapping.root
   [void][IO.Directory]::CreateDirectory($mapping.root)
   $core.SetVirtualHostNameToFolderMapping($mapping.host,$mapping.root,[Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::DenyCors)
  }
  $core.add_NavigationStarting({param($sender,$eventArgs) try{$uri=[Uri]$eventArgs.Uri;if($uri.Scheme -cne 'https' -or $uri.Host -cne 'app.skin.local'){$eventArgs.Cancel=$true}}catch{$eventArgs.Cancel=$true}})
  $core.add_NewWindowRequested({param($sender,$eventArgs) $eventArgs.Handled=$true})
  $core.add_PermissionRequested({param($sender,$eventArgs) $eventArgs.State=[Microsoft.Web.WebView2.Core.CoreWebView2PermissionState]::Deny})
  $core.add_WebMessageReceived({
    param($sender,$eventArgs)
    try{
      $origin=[Uri]$eventArgs.Source
      if($origin.Scheme -cne 'https' -or $origin.Host -cne 'app.skin.local' -or $origin.AbsolutePath -cne '/index.html'){return}
      $json=$eventArgs.WebMessageAsJson;if($json.Length -gt 70000){throw '请求过大。'}
      $request=$json|ConvertFrom-Json
      if($request.id -lt 1 -or $request.id -gt 2147483647 -or "$($request.action)".Length -gt 40){throw '请求无效。'}
      Invoke-HubMessage $request
    }catch{Write-HubLog ($_|Out-String);Send-HubMessage @{id=$request.id;ok=$false;error=$_.Exception.Message}}
  })
  $script:HubReady=$false;$core.Navigate('https://app.skin.local/index.html')
})
$script:SteamView.add_CoreWebView2InitializationCompleted({
  param($sender,$eventArgs)
  if(-not $eventArgs.IsSuccess){Send-SteamHealth 'Steam 浏览组件未能启动，本地功能仍可使用。' $true;return}
  $core=$script:SteamView.CoreWebView2
  $core.IsMuted=$true;$core.Settings.AreDefaultScriptDialogsEnabled=$false;$core.Settings.IsWebMessageEnabled=$false;$core.Settings.AreHostObjectsAllowed=$false;$core.Settings.AreDevToolsEnabled=$false;$core.Settings.IsStatusBarEnabled=$false
  $core.add_NavigationStarting({
    param($sender,$eventArgs)
    if(-not(Test-SteamUri $eventArgs.Uri)){$eventArgs.Cancel=$true;Send-SteamHealth '这个链接请在浏览器中打开。';return}
    $script:SteamUrl=$eventArgs.Uri;$script:SteamLoading=$true;$script:SteamLoadingAt=[DateTime]::UtcNow;$script:SteamSlowShown=$false
    Send-HubMessage @{type='steamUrl';url=$script:SteamUrl};Send-SteamHealth 'Steam 正在加载；可随时浏览本地收藏。'
  })
  $core.add_ContentLoading({param($sender,$eventArgs) if(-not $eventArgs.IsErrorPage){Send-SteamHealth '页面已开始显示，图片仍可能继续加载。'}})
  $core.add_NavigationCompleted({
    param($sender,$eventArgs)
    $script:SteamLoading=$false
    if($eventArgs.IsSuccess){Send-SteamHealth 'Steam 已连接 · 下载后的壁纸可导入'}else{Send-SteamHealth ('Steam 暂未加载成功（'+$eventArgs.WebErrorStatus+'）。可重试或导入已下载壁纸。') $true}
  })
  $core.add_NewWindowRequested({
    param($sender,$eventArgs) $eventArgs.Handled=$true
    if(Test-SteamUri $eventArgs.Uri){$script:SteamView.CoreWebView2.Navigate($eventArgs.Uri)}
    elseif($eventArgs.Uri -match '^steam://url/CommunityFilePage/\d+$'){Open-HubExternal $eventArgs.Uri}
    else{Send-SteamHealth '此链接需要在外部浏览器中打开。'}
  })
  $core.add_PermissionRequested({param($sender,$eventArgs) $eventArgs.State=[Microsoft.Web.WebView2.Core.CoreWebView2PermissionState]::Deny})
  $core.add_DownloadStarting({param($sender,$eventArgs) $eventArgs.Cancel=$true;Send-SteamHealth '请通过 Steam 订阅下载壁纸，完成后可自动导入。'})
  $core.Navigate($script:SteamUrl)
})
$script:WindowSaveDue=[DateTime]::MaxValue
$script:HubForm.add_ResizeEnd({$script:WindowSaveDue=[DateTime]::UtcNow.AddMilliseconds(500)})
$script:HubForm.add_Resize({if($script:HubReady){$script:WindowSaveDue=[DateTime]::UtcNow.AddMilliseconds(500)}})
$script:HubForm.add_FormClosing({Save-DreamHubWindowSettings})
$script:HubTimer=[Windows.Forms.Timer]::new();$script:HubTimer.Interval=400
$script:HubTimer.add_Tick({
  try{
    Update-DreamWuwaHealth
    Update-DreamSteamSubscription
    Update-AriaPendingConnection
    Update-AriaPrivacyMode
    if([DateTime]::UtcNow -ge $script:WindowSaveDue){$script:WindowSaveDue=[DateTime]::MaxValue;Save-DreamHubWindowSettings}
    foreach($pending in @($script:HubPending.ToArray())){
      if(Test-Path -LiteralPath $pending.Path){
        $result=Read-DreamHubJson $pending.Path $null
        if($result){
          if(-not $result.ok -and $result.details){Write-HubLog ('Background action '+$pending.Action+': '+$result.details)}
          if($pending.Action -eq 'launch'){$script:LaunchInFlight=$false;Send-HubMessage @{type='launchDone';message=if($result.ok){$result.message}else{$result.error}}}
          elseif($pending.Id -gt 0){Send-HubMessage $result}
          elseif($pending.Action -eq 'importWuwaDownload'){Send-HubMessage @{type='notice';message=if($result.ok){$result.message}else{$result.error}}}
          elseif(-not $result.ok){Send-HubMessage @{type='launchProgress';message=$result.error}}
          $script:NextData=[DateTime]::MinValue
          [IO.File]::Delete($pending.Path);if(-not $pending.Persistent){$pending.Process.Dispose()};[void]$script:HubPending.Remove($pending)
        }
      }elseif($pending.Process.HasExited){
        $message='后台操作意外结束，请重试。'
        if($pending.Action -eq 'launch'){$script:LaunchInFlight=$false;Send-HubMessage @{type='launchDone';message=$message}}elseif($pending.Id -gt 0){Send-HubMessage @{id=$pending.Id;ok=$false;error=$message}}
        if($pending.Persistent){if(Test-Path -LiteralPath $pending.InputPath){Assert-DreamSkinNoReparseComponents $pending.InputPath;[IO.File]::Delete($pending.InputPath)}}else{$pending.Process.Dispose()};[void]$script:HubPending.Remove($pending)
      }
    }
    if($script:SteamLoading -and -not $script:SteamSlowShown -and ([DateTime]::UtcNow-$script:SteamLoadingAt).TotalSeconds -ge 15){
      $script:SteamSlowShown=$true;Send-SteamHealth 'Steam 响应较慢，仍在尝试连接。你可以重试、用浏览器打开，或先导入已下载壁纸。' $true
    }
    if($script:HubReady -and [DateTime]::UtcNow -ge $script:NextData){
      $script:NextData=[DateTime]::UtcNow.AddSeconds(2)
      $data=Get-DreamHubData;$data|Add-Member -NotePropertyName playbackSettings -NotePropertyValue (Get-AriaPlaybackSettings) -Force;$data|Add-Member -NotePropertyName privacySettings -NotePropertyValue (Get-AriaPrivacySettings) -Force;$data|Add-Member -NotePropertyName desktopConnection -NotePropertyValue (Get-AriaDesktopConnection) -Force;$json=$data|ConvertTo-Json -Depth 14 -Compress
      if($json -cne $script:LastData){$script:LastData=$json;Send-HubMessage @{type='state';data=$data}}
      Update-AriaJobNotices -Jobs @($script:AriaRawJobsForNotices) -HiddenIds @(Get-AriaHiddenIds) -PublicIds @($data.themes.id)
      if($TestMode){Write-DreamHubJson (Join-Path $script:HubCodeRoot 'outputs\host-status.json') @{ready=$true;steamStarted=$script:SteamStarted;steamLoading=$script:SteamLoading;steamWanted=$script:SteamWanted;themes=$data.themes.Count;jobs=$data.jobs.Count;url=$script:SteamUrl;steamMessage=$script:SteamHealthMessage;steamError=$script:SteamHealthError;dpi=[DreamHubDisplay]::GetDpiForWindow($script:HubForm.Handle);perMonitorV2=[DreamHubDisplay]::IsPerMonitorV2($script:HubForm.Handle);clientWidth=$script:HubView.ClientSize.Width;clientHeight=$script:HubView.ClientSize.Height;zoom=$script:HubView.ZoomFactor;wuwaStarted=$script:WuwaStarted;wuwaLoading=$script:WuwaLoading;wuwaWanted=$script:WuwaWanted;wuwaError=$script:WuwaHealthError;wuwaMessage=$script:WuwaHealthMessage;steamSubscriptionStatus=$script:SteamSubscriptionLast;steamSubscriptionIntent=([bool]$script:SteamSubscriptionIntent)}}
    }
    if($TestMode){
      $path=Join-Path $script:HubCodeRoot 'outputs\host-test.json'
      if(Test-Path -LiteralPath $path){
        $test=Read-DreamHubJson $path $null;[IO.File]::Delete($path)
        if($test.finishTest){$script:TestMode=$false;Write-DreamHubJson (Join-Path $script:HubCodeRoot 'outputs\test-mode-finished.json') @{finishedAt=[DateTime]::UtcNow.ToString('o');testMode=$false}}
        if($test.measureDisplay){$script:DisplayProbe=$script:HubView.CoreWebView2.ExecuteScriptAsync("({dpr:devicePixelRatio,width:innerWidth,height:innerHeight,screenWidth:screen.width,screenHeight:screen.height,bodyWidth:document.body.scrollWidth,skinCards:document.querySelectorAll('#skinGrid .card').length,navigationRects:[...document.querySelectorAll('nav .nav-emoji')].map(i=>{const r=i.getBoundingClientRect();return {page:i.closest('button').dataset.page,x:r.x,y:r.y,width:r.width,height:r.height,src:i.currentSrc}}),libraryCount:document.getElementById('libraryCount').textContent})")}
        if($test.action -in @('favorite','opacity','savePrompt','deletePrompt','savePolicy','importHero','launch','launchDesktop','importWorkshop','windowPreset','windowRemember')){Invoke-HubMessage $test}
        if($test.page -in @('home','library','workshop','wuwa','jobs','prompts','settings')){$null=$script:HubView.CoreWebView2.ExecuteScriptAsync("go('"+$test.page+"')")}
        if($test.steamGo){Invoke-HubMessage ([pscustomobject]@{id=0;action='steamGo';url=[string]$test.steamGo})}
        if($test.wuwaGo -and (Test-DreamWuwaUri ([string]$test.wuwaGo)) -and $script:WuwaView.CoreWebView2){$script:WuwaView.CoreWebView2.Navigate([string]$test.wuwaGo)}
        if($test.openWuwaImages){$null=$script:HubView.CoreWebView2.ExecuteScriptAsync('AriaWuwaImages.open()')}
        if($test.openDownloaded){$null=$script:HubView.CoreWebView2.ExecuteScriptAsync('AriaDownloads.open()')}

        if($test.slowSteam){$script:SteamLoading=$true;$script:SteamLoadingAt=[DateTime]::UtcNow.AddSeconds(-16);$script:SteamSlowShown=$false}
        if($test.capture -in @('home','library','workshop','jobs','prompts','settings','steam','wuwa')){
          $stream=[IO.File]::Create((Join-Path $script:HubCodeRoot ('outputs\ui-'+$test.capture+'.png')))
          $captureView=if($test.capture -eq 'steam'){$script:SteamView}elseif($test.capture -eq 'wuwa'){$script:WuwaView}else{$script:HubView}
          $task=$captureView.CoreWebView2.CapturePreviewAsync([Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png,$stream)
          $script:CapturePending=[pscustomobject]@{Task=$task;Stream=$stream}
        }
      }
      if($script:DisplayProbe -and $script:DisplayProbe.IsCompleted){$measure=$script:DisplayProbe.Result|ConvertFrom-Json;Write-DreamHubJson (Join-Path $script:HubCodeRoot 'outputs\display-metrics.json') $measure;$script:DisplayProbe=$null}
      if($script:CapturePending -and $script:CapturePending.Task.IsCompleted){$script:CapturePending.Stream.Dispose();$script:CapturePending=$null}
    }
  }catch{Write-HubLog ($_|Out-String)}
})
$script:HubForm.add_Shown({$null=$script:HubView.EnsureCoreWebView2Async($null);$script:HubTimer.Start()})
$script:HubForm.add_FormClosed({Lock-AriaHidden;Lock-AriaAdmin;$script:HubTimer.Stop();$script:WuwaView.Dispose();$script:SteamView.Dispose();$script:HubView.Dispose();foreach($pending in $script:HubPending){if(-not $pending.Persistent){$pending.Process.Dispose()}};if($script:AriaLaunchWorker){$script:AriaLaunchWorker.Dispose()}})
try{[Windows.Forms.Application]::Run($script:HubForm)}catch{Write-HubLog ($_|Out-String);[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Aria启动失败')}finally{if($script:OwnHubInstance){$script:HubInstance.ReleaseMutex()};$script:HubInstance.Dispose()}
