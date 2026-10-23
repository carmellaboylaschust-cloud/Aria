$script:AriaPrivacyPending=$false
function Get-AriaPrivacySettings {
 $value=Read-DreamHubJson (Join-Path $script:DreamHubHome 'privacy-preferences.json') $null
 return [pscustomobject]@{safeThemeId=if($value.schemaVersion -eq 1){[string]$value.safeThemeId}else{''}}
}
function Save-AriaPrivacySettings {
 param([string]$ThemeId)
 if($ThemeId){
  if($ThemeId -in @(Get-AriaHiddenIds)){throw '隐私模式只能使用普通皮肤。'}
  $null=Get-DreamHubThemeById $ThemeId
 }
 Write-DreamHubJson (Join-Path $script:DreamHubHome 'privacy-preferences.json') @{schemaVersion=1;safeThemeId=$ThemeId}
}
function Change-AriaAdminPassword {
 param([string]$CurrentPassword,[string]$NewPassword,[string]$Confirmation)
 if(-not(Test-AriaGrant -Role admin)){throw '请先完成管理员验证。'}
 Assert-AriaAttemptAllowed
 if($CurrentPassword.Length -gt 256 -or $NewPassword.Length -gt 128 -or $NewPassword.Trim().Length -lt 12){throw '新密码需为 12 至 128 字。'}
 if($NewPassword -cne $Confirmation){throw '两次新密码不一致。'}
 $config=Get-AriaPrivacyConfig
 if(-not[AriaPrivacyCrypto]::Verify($CurrentPassword,$config.password.salt,$config.password.hash)){Register-AriaFailedAttempt;throw '当前管理员密码不正确。'}
 $salt=[AriaPrivacyCrypto]::Random();$config.password=[pscustomobject]@{salt=$salt;hash=[AriaPrivacyCrypto]::Hash($NewPassword,$salt)}
 Write-AriaPrivacyConfig $config
 Lock-AriaHidden;Lock-AriaAdmin
 $folder=Join-Path $script:AriaPrivacyRoot 'grants'
 if(Test-Path -LiteralPath $folder){
  Assert-DreamSkinNoReparseComponents $folder
  foreach($file in @(Get-ChildItem -LiteralPath $folder -File|Where-Object Name -CMatch '^[a-f0-9]{64}\.dat$')){Assert-DreamSkinNoReparseComponents $file.FullName;[IO.File]::Delete($file.FullName)}
 }
 $script:AriaPrivacyFailures=0
}
function Invoke-AriaPrivacyMode {
 Lock-AriaHidden;Lock-AriaAdmin;Send-HubMessage @{type='privacyLocked'};$script:NextData=[DateTime]::MinValue
 if($script:LaunchInFlight){$script:AriaPrivacyPending=$true;return '隐藏列表已锁定，当前切换结束后会接续换回普通背景。'}
 $script:AriaPrivacyPending=$false
 $active=Read-DreamHubJson (Join-Path $script:DreamHubState 'active-theme\theme.json') $null
 if($active.id -notin @(Get-AriaHiddenIds)){return '隐藏列表已锁定，当前背景为普通皮肤。'}
 $connection=Get-AriaDesktopConnection
 if($connection.status -eq 'closed'){return '隐藏列表已锁定。桌面端尚未运行，本次没有启动它。'}
 if($connection.status -ne 'connected'){return '隐藏列表已锁定；桌面端未连接，暂时无法替换其背景。'}
 $data=Get-DreamHubData;$settings=Get-AriaPrivacySettings
 $safe=@($data.themes|Where-Object id -CEQ $settings.safeThemeId|Select-Object -First 1)
 if(-not $safe.Count){$safe=@($data.themes|Sort-Object lastUsed -Descending|Select-Object -First 1)}
 if(-not $safe.Count){return '隐藏列表已锁定，但没有可用的普通背景，请先添加一张。'}
 $script:LaunchInFlight=$true
 Start-HubAction ([pscustomobject]@{id=0;action='launch';themeId=$safe[0].id;prompt='';privacyMode=$true})
 Send-HubMessage @{type='launchProgress';message='隐藏列表已锁定，正在替换为普通背景。'}
 return '隐藏列表已锁定，正在换回普通背景。'
}
function Update-AriaPrivacyMode {
 if($script:AriaPrivacyPending -and -not $script:LaunchInFlight){$message=Invoke-AriaPrivacyMode;Send-HubMessage @{type='notice';message=$message}}
}

function Get-AriaPlaybackSettings {
 $value=Read-DreamHubJson (Join-Path $script:DreamHubHome 'playback-settings.json') $null
 return [pscustomobject]@{mode=if($value.mode -in @('normal','battery','static')){[string]$value.mode}else{'normal'}}
}
function Save-AriaPlaybackSettings {
 param([ValidateSet('normal','battery','static')][string]$Mode)
 Write-DreamHubJson (Join-Path $script:DreamHubHome 'playback-settings.json') @{schemaVersion=1;mode=$Mode}
}
