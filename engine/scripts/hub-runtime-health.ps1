function Test-AriaStalledSnapshot {
  param($Pending,[DateTime]$Now=[DateTime]::UtcNow)
  # Launch, backup and media tasks keep their own duration rules.
  if($Pending.Action -ne 'snapshot' -or -not $Pending.Persistent){return $false}
  if(-not [object]::ReferenceEquals($Pending.Process,$script:AriaSnapshotWorker)){return $false}
  if(($Now-$Pending.Started).TotalSeconds -lt 30){return $false}
  if(Test-Path -LiteralPath $Pending.Path){
    # A truncated or null result must not hold the single snapshot slot forever.
    try{
      Assert-DreamSkinNoReparseComponents $Pending.Path
      $result=[IO.File]::ReadAllText($Pending.Path)|ConvertFrom-Json
      if($result -and $result.ok -is [bool]){return $false}
    }catch{}
  }
  return $true
}
function Reset-AriaStalledSnapshot {
  param($Pending)
  if(-not(Test-AriaStalledSnapshot $Pending)){return $false}
  $worker=$Pending.Process
  try{
    if(-not $worker.HasExited){$worker.Kill();if(-not $worker.WaitForExit(200)){return $false}}
    foreach($item in @($script:HubPending.ToArray()|Where-Object {$_.Action -eq 'snapshot' -and [object]::ReferenceEquals($_.Process,$worker)})){
      foreach($path in @($item.InputPath,$item.InputPath.Replace('.request.json','.processing.json'),$item.Path)){
        if((Test-DreamSkinPathWithin $path $script:HubRequests) -and [IO.File]::Exists($path)){Assert-DreamSkinNoReparseComponents $path;[IO.File]::Delete($path)}
      }
      [void]$script:HubPending.Remove($item)
    }
    $script:AriaSnapshotWorker=$null;$worker.Dispose();$script:HubGeneration++
    $script:NextData=[DateTime]::UtcNow.AddSeconds(2)
    Write-AriaSnapshotError 'Snapshot exceeded its 30-second deadline; restarting the snapshot worker.'
    if(-not $script:SnapshotRecoveryNoticeAt -or ([DateTime]::UtcNow-$script:SnapshotRecoveryNoticeAt).TotalMinutes -ge 2){
      $script:SnapshotRecoveryNoticeAt=[DateTime]::UtcNow
      Send-HubMessage @{type='notice';message='正在恢复皮肤库连接，可以继续浏览。'}
    }
    return $true
  }catch{Write-AriaSnapshotError ('Snapshot recovery: '+$_.Exception.Message);return $false}
}
function Update-AriaThumbnailSchedule {
  # New imports prepare promptly; unchanged libraries reconcile every five minutes.
  $missing=@(@($script:HubLatestData.themes)+@($script:HubLatestData.hiddenThemes)|Where-Object {$_ -and -not $_.thumbnail}|ForEach-Object id|Sort-Object -Unique) -join '|'
  if($missing -cne $script:LastMissingThumbs){$script:LastMissingThumbs=$missing;if($missing){$script:LastThumbCheck=[DateTime]::MinValue}}
}
