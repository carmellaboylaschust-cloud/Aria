$script:SteamSubscriptionAdapter=[IO.File]::ReadAllText((Join-Path $script:HubCodeRoot 'hub\steam-subscription.js'))
$script:SteamSubscriptionIntent=$null;$script:SteamSubscriptionTask=$null;$script:SteamSubscriptionLast=$null;$script:SteamSubscriptionNext=[DateTime]::MinValue;$script:SteamSubscriptionQueued=@{}
function Get-DreamSteamPageId {
 try{$url=[Uri]$script:SteamUrl;if($url.Scheme -cne 'https' -or $url.Host -cne 'steamcommunity.com' -or $url.AbsolutePath -cne '/sharedfiles/filedetails/'){return $null};if($url.Query -match '(?:\?|&)id=(\d{6,12})(?:&|$)'){return $Matches[1]}}catch{}
 return $null
}
function Start-DreamSteamSubscribeAndImport {
 $id=Get-DreamSteamPageId
 if(-not $id){throw '请先打开一张具体的 Wallpaper Engine 壁纸。'}
 if(-not $script:SteamView.CoreWebView2 -or $script:SteamLoading){throw '壁纸页还在加载，请稍等片刻。'}
 $script:SteamSubscriptionQueued.Remove($id)
 $script:SteamSubscriptionIntent=[pscustomobject]@{Id=$id;WantSubmit=$true;Expires=[DateTime]::UtcNow.AddMinutes(10)}
 $script:SteamSubscriptionNext=[DateTime]::MinValue
 Send-SteamHealth '正在确认订阅；完成后自动进入下载和导入队列。'
}
function Complete-DreamSteamSubscription {
 param([string]$Id,[bool]$OpenJobs)
 if($script:SteamSubscriptionQueued.ContainsKey($Id)){return}
 $script:SteamSubscriptionQueued[$Id]=$true
 Start-HubAction ([pscustomobject]@{id=0;action='workshopImport';workshopId=$Id})
 Send-SteamHealth '已接收订阅，Steam 后台下载完成后会自动导入。'
 Send-HubMessage @{type='steamSubscriptionQueued';openJobs=$false}
}
function Update-DreamSteamSubscription {
 if($script:SteamSubscriptionTask -and $script:SteamSubscriptionTask.Task.IsCompleted){
  $probe=$script:SteamSubscriptionTask;$script:SteamSubscriptionTask=$null
  try{
   $result=$probe.Task.Result|ConvertFrom-Json
   if($result.id -ceq $probe.Id){
    switch($result.status){
     'subscribed' {
      $intent=$script:SteamSubscriptionIntent -and $script:SteamSubscriptionIntent.Id -ceq $probe.Id
      $changed=$script:SteamSubscriptionLast -and $script:SteamSubscriptionLast.Id -ceq $probe.Id -and $script:SteamSubscriptionLast.Status -eq 'unsubscribed'
      if(($intent -or $changed) -and $result.clientMatches -eq $false){
       $script:SteamSubscriptionIntent=$null;Send-SteamHealth '商城与 Steam 客户端登录的账号不同，请在两处使用同一账号后重试。' $true
      }elseif($intent -or $changed){Complete-DreamSteamSubscription $probe.Id ([bool]$intent);if($intent){$script:SteamSubscriptionIntent=$null}}
     }
     'login-required' {
      if($script:SteamSubscriptionIntent -and $script:SteamSubscriptionIntent.Id -ceq $probe.Id){
       $script:SteamSubscriptionIntent.WantSubmit=$true
       $return='/sharedfiles/filedetails/?id='+$probe.Id+'&l=schinese'
       Send-SteamHealth '请在商城里登录 Steam，登录返回后会自动继续。'
       $script:SteamView.CoreWebView2.Navigate('https://steamcommunity.com/login/home/?goto='+[Uri]::EscapeDataString($return))
      }
     }
     'submitted' {Send-SteamHealth '已点击 Steam 官方订阅按钮，正在等待确认；如页面要求确认，请在页内完成。'}
     {$_ -in @('wrong-app','unsupported','error')} {
      if($script:SteamSubscriptionIntent -and $script:SteamSubscriptionIntent.Id -ceq $probe.Id){
       $script:SteamSubscriptionIntent=$null
       Send-SteamHealth '此页未能确认可订阅的 Wallpaper Engine 壁纸。请使用页面内的订阅按钮，或稍后重试。' $true
      }
     }
    }
    if($result.status -in @('subscribed','unsubscribed')){$script:SteamSubscriptionLast=[pscustomobject]@{Id=$probe.Id;Status=$result.status;ClientMatches=$result.clientMatches}}
   }
  }catch{Write-HubLog ('Steam subscription observation: '+$_.Exception.Message)}
 }
 if($script:SteamSubscriptionIntent -and [DateTime]::UtcNow -gt $script:SteamSubscriptionIntent.Expires){$script:SteamSubscriptionIntent=$null;Send-SteamHealth '订阅等待已超时，请完成 Steam 页面中的提示后重试。' $true}
 if($script:SteamSubscriptionTask -or [DateTime]::UtcNow -lt $script:SteamSubscriptionNext -or -not $script:SteamWanted -or $script:SteamLoading -or -not $script:SteamView.CoreWebView2){return}
 $id=Get-DreamSteamPageId;if(-not $id){$script:SteamSubscriptionLast=$null;return}
 $submit=$script:SteamSubscriptionIntent -and $script:SteamSubscriptionIntent.Id -ceq $id -and $script:SteamSubscriptionIntent.WantSubmit
 if($submit){$script:SteamSubscriptionIntent.WantSubmit=$false}
 $clientId='null'
 try{$clientUser=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction Stop).ActiveUser;if($clientUser -gt 0){$clientId='"'+([UInt64]76561197960265728+[UInt64]$clientUser).ToString()+'"'}}catch{}
 $code=$script:SteamSubscriptionAdapter.Replace('__ARIA_ID__',('"'+$id+'"')).Replace('__ARIA_CLIENT__',$clientId).Replace('__ARIA_TRIGGER__',$(if($submit){'true'}else{'false'}))
 $script:SteamSubscriptionTask=[pscustomobject]@{Id=$id;Task=$script:SteamView.CoreWebView2.ExecuteScriptAsync($code)}
 $script:SteamSubscriptionNext=[DateTime]::UtcNow.AddMilliseconds(800)
}
