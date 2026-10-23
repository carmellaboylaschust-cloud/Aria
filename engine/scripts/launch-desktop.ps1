param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
foreach($ariaModule in @('common-windows','theme-windows','background-library','scene-queue','hub-workshop','hub-data','hub-feed')){. (Join-Path $PSScriptRoot ($ariaModule+'.ps1'))}
try{
 $ariaState=Read-DreamSkinState -Path (Join-Path $script:DreamHubState 'state.json')
 $ariaInstall=if($ariaState){Get-DreamSkinCodexInstallFromState $ariaState}else{$null}
 $ariaRunning=@(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue|Where-Object {try{$_.Path -like '*\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe'}catch{$false}})
 $ariaLive=if($ariaInstall){Get-DreamSkinVerifiedCdpIdentity -Port $ariaState.port -Codex $ariaInstall}else{$null}
 $ariaData=Get-DreamHubData
 $ariaTheme=@($ariaData.themes|Where-Object {$_.id -ceq $ariaData.activeId}|Select-Object -First 1)
 if(-not $ariaTheme.Count){$ariaTheme=@($ariaData.themes|Select-Object -First 1)}
 if($CheckOnly){[pscustomobject]@{running=[bool]$ariaRunning.Count;connected=[bool]$ariaLive;publicSkinAvailable=[bool]$ariaTheme.Count;willCloseExisting=$false}|ConvertTo-Json -Compress;exit 0}
 if($ariaRunning.Count -and -not $ariaLive){
  Write-DreamHubJson (Join-Path $script:DreamHubHome 'desktop-connection-needed.json') @{at=[DateTime]::UtcNow.ToString('o');message='桌面端已从原入口打开，尚未建立换肤连接。可在 Aria 点击“打开并连接桌面端”，保存工作并自行退出后，会自动接续带背景启动。'}
  Start-Process -FilePath (Join-Path $script:DreamHubHome 'Aria.exe') -WindowStyle Hidden
  exit 0
 }
 if(-not $ariaTheme.Count){Start-Process -FilePath (Join-Path $script:DreamHubHome 'Aria.exe') -WindowStyle Hidden;exit 0}
 $ariaSelected=Get-DreamHubThemeById $ariaTheme[0].id
 $ariaToken=[guid]::NewGuid().ToString('N')
 & (Join-Path $PSScriptRoot 'apply-or-start.ps1') -SavedThemeDirectory $ariaSelected.Directory -ResultToken $ariaToken
 $ariaResult=Read-DreamSkinStartResult -StateRoot $script:DreamHubState -Token $ariaToken
 if($ariaResult.outcome -ne 'success'){throw '桌面端暂未连接成功，请在 Aria 中查看状态。'}
 $ariaState=Read-DreamSkinState -Path (Join-Path $script:DreamHubState 'state.json');$ariaInstall=Get-DreamSkinCodexInstallFromState $ariaState
 if($ariaInstall){[void](Invoke-DreamSkinCodexWindowActivation -Codex $ariaInstall)}
}catch{
 [IO.File]::AppendAllText((Join-Path $script:DreamHubHome 'desktop-launch.log'),[DateTime]::Now.ToString('s')+' '+$_.Exception.Message+[Environment]::NewLine)
 if($CheckOnly){throw}
 Start-Process -FilePath (Join-Path $script:DreamHubHome 'Aria.exe') -WindowStyle Hidden
}
