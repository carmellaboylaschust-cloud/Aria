$script:AriaConnectPending=$null;$script:AriaConnectionCache=$null;$script:AriaConnectionDue=[DateTime]::MinValue
function Get-AriaDesktopConnection {
 if($script:AriaConnectionCache -and [DateTime]::UtcNow -lt $script:AriaConnectionDue){return $script:AriaConnectionCache}
 $script:AriaConnectionDue=[DateTime]::UtcNow.AddSeconds(5)
 $running=@(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue|Where-Object {try{$_.Path -like '*\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe'}catch{$false}})
 $status=if($running.Count){'unconnected'}else{'closed'}
 try{
  $state=Read-DreamHubJson (Join-Path $script:DreamHubState 'state.json') $null
  if($running.Count -and $state.port -gt 1024 -and @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -eq $state.port).Count){
   $request=[Net.HttpWebRequest]::Create('http://127.0.0.1:'+([int]$state.port)+'/json/version');$request.Proxy=$null;$request.Timeout=350;$request.ReadWriteTimeout=350
   $response=$request.GetResponse();try{$reader=[IO.StreamReader]::new($response.GetResponseStream());try{$version=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}}finally{$response.Dispose()}
   if([string]$version.webSocketDebuggerUrl -clike ('*/'+$state.browserId)){$status='connected'}
  }
 }catch{}
 $script:AriaConnectionCache=[pscustomobject]@{status=$status;waitingForExit=([bool]$script:AriaConnectPending)}
 return $script:AriaConnectionCache
}
function Update-AriaPendingConnection {
 if(-not $script:AriaConnectPending){return}
 if([DateTime]::UtcNow -gt $script:AriaConnectPending){$script:AriaConnectPending=$null;$script:AriaConnectionDue=[DateTime]::MinValue;Send-HubMessage @{type='notice';message='连接等待已结束，需要时可再次点击等待退出。'};return}
 $connection=Get-AriaDesktopConnection
 if($connection.status -ne 'closed' -or $script:LaunchInFlight){return}
 $script:AriaConnectPending=$null;$script:AriaConnectionDue=[DateTime]::MinValue
 $data=Get-DreamHubData;$theme=@($data.themes|Where-Object id -ceq $data.activeId|Select-Object -First 1);if(-not $theme.Count){$theme=@($data.themes|Select-Object -First 1)}
 if(-not $theme.Count){Send-HubMessage @{type='notice';message='请先选择一张普通皮肤，再启动桌面端。'};return}
 $script:LaunchInFlight=$true;Start-HubAction ([pscustomobject]@{id=0;action='launch';themeId=$theme[0].id;prompt=''})
 Send-HubMessage @{type='launchProgress';message='已检测到桌面端退出，正在接续带背景启动。'}
}

function Start-AriaDesktopFromHub {
 if($script:LaunchInFlight){throw '桌面端正在启动，请稍等。'}
 $script:AriaConnectionDue=[DateTime]::MinValue
 $connection=Get-AriaDesktopConnection
 if($connection.status -eq 'unconnected'){
  $script:AriaConnectPending=[DateTime]::UtcNow.AddMinutes(10);$script:AriaConnectionDue=[DateTime]::MinValue;$script:NextData=[DateTime]::MinValue
  return [pscustomobject]@{waitingForExit=$true;message='已等待连接。请保存工作并自行退出桌面端，Aria 会自动带背景启动，无需快捷方式。'}
 }
 $data=Get-DreamHubData;$theme=@($data.themes|Where-Object id -ceq $data.activeId|Select-Object -First 1)
 if(-not $theme.Count){$theme=@($data.themes|Select-Object -First 1)}
 if(-not $theme.Count){throw '请先在“我的皮肤”添加一张普通背景。'}
 $script:LaunchInFlight=$true
 try{Start-HubAction ([pscustomobject]@{id=0;action='launch';themeId=$theme[0].id;prompt=''})}catch{$script:LaunchInFlight=$false;throw}
 Send-HubMessage @{type='launchProgress';message='正在打开桌面端并连接换肤服务，可以继续浏览。'}
 return [pscustomobject]@{waitingForExit=$false;message='正在打开桌面端并连接换肤服务'}
}
