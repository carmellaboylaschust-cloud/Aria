$script:HubLatestData=$null
$script:HubGeneration=0
$script:SnapshotErrorDue=[DateTime]::MinValue
function Write-AriaSnapshotError {
 param([string]$Message)
 if($Message -match 'Another theme import is still running'){return}
 if([DateTime]::UtcNow -ge $script:SnapshotErrorDue){$script:SnapshotErrorDue=[DateTime]::UtcNow.AddSeconds(30);Write-HubLog ('Snapshot: '+$Message)}
}
function Test-AriaSnapshotAuthorization {
 param([string]$RequestedToken,[string]$CurrentToken,[bool]$GrantValid)
 if($RequestedToken -cne $CurrentToken){return $false}
 return (-not $RequestedToken -or $GrantValid)
}
function Publish-AriaSnapshot {
 param($Result,$Pending)
 $token=[string]$Pending.SnapshotToken
 if($token -cne [string]$script:AriaHiddenToken){$script:NextData=[DateTime]::MinValue;return}
 $valid=if($token){Test-AriaGrant -Token $token -Role hidden}else{$false}
 if($token -and -not $valid){Lock-AriaHidden;$script:HubLatestData=$null;$script:LastData='';Send-HubMessage @{type='privacyLocked'};$script:NextData=[DateTime]::MinValue;return}
 if(-not(Test-AriaSnapshotAuthorization -RequestedToken $token -CurrentToken ([string]$script:AriaHiddenToken) -GrantValid $valid) -or $Pending.Generation -ne $script:HubGeneration){$script:NextData=[DateTime]::MinValue;return}
 $snapshot=[AriaPrivacyCrypto]::Unprotect([string]$Result.protectedSnapshot)|ConvertFrom-Json
 $data=$snapshot.data
 if(-not $data -or -not $data.desktopConnection){throw '皮肤库快照无效。'}
 $data.desktopConnection.waitingForExit=[bool]$script:AriaConnectPending
 $script:HubLatestData=$data
 $json=$data|ConvertTo-Json -Depth 14 -Compress
 if($json -cne $script:LastData){$script:LastData=$json;Send-HubMessage @{type='state';data=$data}}
 Update-AriaJobNotices -Jobs @($snapshot.completedJobs) -HiddenIds @() -PublicIds @($data.themes.id)
 if($TestMode){Write-DreamHubJson (Join-Path $script:HubCodeRoot 'outputs\host-status.json') @{ready=$true;steamStarted=$script:SteamStarted;steamLoading=$script:SteamLoading;steamWanted=$script:SteamWanted;themes=$data.themes.Count;jobs=$data.jobs.Count;url=$script:SteamUrl;steamMessage=$script:SteamHealthMessage;steamError=$script:SteamHealthError;dpi=[DreamHubDisplay]::GetDpiForWindow($script:HubForm.Handle);perMonitorV2=[DreamHubDisplay]::IsPerMonitorV2($script:HubForm.Handle);clientWidth=$script:HubView.ClientSize.Width;clientHeight=$script:HubView.ClientSize.Height;zoom=$script:HubView.ZoomFactor;wuwaStarted=$script:WuwaStarted;wuwaLoading=$script:WuwaLoading;wuwaWanted=$script:WuwaWanted;wuwaError=$script:WuwaHealthError;wuwaMessage=$script:WuwaHealthMessage;steamSubscriptionStatus=$script:SteamSubscriptionLast;steamSubscriptionIntent=([bool]$script:SteamSubscriptionIntent)}}
}
