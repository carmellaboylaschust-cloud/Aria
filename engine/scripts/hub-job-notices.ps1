$script:AriaCompletedSeen=$null
function Update-AriaJobNotices {
 param([object[]]$Jobs,[string[]]$HiddenIds,[string[]]$PublicIds)
 $completed=@($Jobs|Where-Object {$_.status -eq 'completed' -and -not $_.testOnly})
 if($null -eq $script:AriaCompletedSeen){$script:AriaCompletedSeen=@{};foreach($job in $completed){$script:AriaCompletedSeen[[string]$job.id]=$true};return}
 foreach($job in $completed){
  if($script:AriaCompletedSeen.ContainsKey([string]$job.id)){continue}
  $script:AriaCompletedSeen[[string]$job.id]=$true
  if($job.themeId -and $job.themeId -notin $HiddenIds -and $job.themeId -in $PublicIds){Send-HubMessage @{type='jobCompleted';name=[string]$job.name;themeId=[string]$job.themeId}}
 }
}
