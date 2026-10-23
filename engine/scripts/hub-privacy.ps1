if(-not ('AriaPrivacyCrypto' -as [type])){
Add-Type -ReferencedAssemblies System.Security -TypeDefinition @'
using System;using System.Text;using System.Security.Cryptography;
public static class AriaPrivacyCrypto {
 public static string Random(){var b=new byte[32];using(var r=RandomNumberGenerator.Create())r.GetBytes(b);return Convert.ToBase64String(b);}
 public static string Hash(string value,string salt){using(var k=new Rfc2898DeriveBytes(value.Normalize().Trim(),Convert.FromBase64String(salt),120000,HashAlgorithmName.SHA256))return Convert.ToBase64String(k.GetBytes(32));}
 public static bool Verify(string value,string salt,string expected){var a=Convert.FromBase64String(Hash(value,salt));var b=Convert.FromBase64String(expected);int d=a.Length^b.Length;for(int i=0;i<a.Length&&i<b.Length;i++)d|=a[i]^b[i];return d==0;}
 public static string Key(string token){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(Encoding.UTF8.GetBytes(token))).Replace("-","").ToLowerInvariant();}
 public static string Protect(string text){return Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(text),Encoding.UTF8.GetBytes("Aria-Privacy-v1"),DataProtectionScope.CurrentUser));}
 public static string Unprotect(string text){return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(text),Encoding.UTF8.GetBytes("Aria-Privacy-v1"),DataProtectionScope.CurrentUser));}
}
'@
}
if(-not(Get-Variable AriaPrivacyRoot -Scope Script -ErrorAction SilentlyContinue)){$script:AriaPrivacyRoot='D:\Aria\user-backgrounds\privacy'}
if(-not(Get-Variable AriaHiddenToken -Scope Script -ErrorAction SilentlyContinue)){$script:AriaHiddenToken='';$script:AriaAdminToken='';$script:AriaPrivacyChallenge=$null;$script:AriaPrivacyFailures=0;$script:AriaPrivacyRetryAfter=[DateTime]::MinValue}
$script:AriaRequestHiddenToken=''
function Get-AriaPrivacyConfig {
 $path=Join-Path $script:AriaPrivacyRoot 'vault.dat';Assert-DreamSkinNoReparseComponents $path
 if(-not(Test-Path -LiteralPath $path)){throw '隐藏皮肤尚未初始化。'}
 $blob=[IO.File]::ReadAllText($path)
 return ([AriaPrivacyCrypto]::Unprotect($blob)|ConvertFrom-Json)
}
function Write-AriaPrivacyConfig {
 param($Config)
 Assert-DreamSkinNoReparseComponents $script:AriaPrivacyRoot;[void][IO.Directory]::CreateDirectory($script:AriaPrivacyRoot)
 $blob=[AriaPrivacyCrypto]::Protect(($Config|ConvertTo-Json -Depth 12 -Compress))
 Write-DreamSkinUtf8FileAtomically -Path (Join-Path $script:AriaPrivacyRoot 'vault.dat') -Content $blob
}
function Test-AriaPrivacyInitialized {
 $path=Join-Path $script:AriaPrivacyRoot 'vault.dat'
 Assert-DreamSkinNoReparseComponents $path
 return (Test-Path -LiteralPath $path -PathType Leaf)
}
function Initialize-AriaPrivacy {
 param([string]$Password,[string]$Confirmation,[object[]]$Questions)
 if($Password.Trim().Length -lt 12 -or $Password.Length -gt 128){throw '请设置 12 至 128 字的管理员密码。'}
 if($Password -cne $Confirmation){throw '请确认两次密码完全一致。'}
 if($Questions.Count -lt 1 -or $Questions.Count -gt 20){throw '请设置 1 至 20 个验证问题。'}
 $entries=@();$seen=@{}
 foreach($item in $Questions){
  $q=([string]$item.question).Trim();$a=([string]$item.answer).Trim()
  if($q.Length -lt 2 -or $q.Length -gt 100 -or $a.Length -lt 1 -or $a.Length -gt 64){throw '问题需为 2 至 100 字，答案需为 1 至 64 字。'}
  if($seen.ContainsKey($q)){throw '请为每个问题使用独立的题目。'};$seen[$q]=$true
  $salt=[AriaPrivacyCrypto]::Random()
  $entries+=@([pscustomobject]@{id=[guid]::NewGuid().ToString('N');question=$q;salt=$salt;hash=[AriaPrivacyCrypto]::Hash($a,$salt)})
 }
 $mutex=[Threading.Mutex]::new($false,('Local\Aria.PrivacySetup.'+[AriaPrivacyCrypto]::Key($script:AriaPrivacyRoot)))
 $held=$false
 try{
  try{$held=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(-not $held){throw '设置正在保存，请稍后重试。'}
  if(Test-AriaPrivacyInitialized){throw '管理员已设置，请使用密码验证入口。'}
  $salt=[AriaPrivacyCrypto]::Random()
  Write-AriaPrivacyConfig ([pscustomobject]@{schemaVersion=1;password=[pscustomobject]@{salt=$salt;hash=[AriaPrivacyCrypto]::Hash($Password,$salt)};questions=$entries;hiddenIds=@()})
 }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Get-AriaHiddenIds {if(-not(Test-Path -LiteralPath (Join-Path $script:AriaPrivacyRoot 'vault.dat'))){return @()};return @((Get-AriaPrivacyConfig).hiddenIds)}
function Get-AriaGrantPath {param([string]$Token) if(-not $Token -or $Token.Length -gt 100){return $null};return (Join-Path (Join-Path $script:AriaPrivacyRoot 'grants') ([AriaPrivacyCrypto]::Key($Token)+'.dat'))}
function New-AriaGrant {
 param([ValidateSet('hidden','admin')][string]$Role)
 $token=[AriaPrivacyCrypto]::Random();$folder=Join-Path $script:AriaPrivacyRoot 'grants';Assert-DreamSkinNoReparseComponents $folder;[void][IO.Directory]::CreateDirectory($folder)
 $data=@{role=$Role;ownerPid=$PID;ownerStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');expires=[DateTime]::UtcNow.AddMinutes(15).ToString('o')}
 Write-DreamSkinUtf8FileAtomically -Path (Get-AriaGrantPath $token) -Content ([AriaPrivacyCrypto]::Protect(($data|ConvertTo-Json -Compress)))
 return $token
}
function Test-AriaGrant {
 param([string]$Token,[ValidateSet('hidden','admin')][string]$Role='hidden')
 if(-not $Token){$Token=if($Role -eq 'admin'){$script:AriaAdminToken}else{$script:AriaHiddenToken};if(-not $Token -and $Role -eq 'hidden'){$Token=$script:AriaRequestHiddenToken}}
 if(-not $Token){return $false}
 try{
  $path=Get-AriaGrantPath $Token;Assert-DreamSkinNoReparseComponents $path
  $data=[AriaPrivacyCrypto]::Unprotect([IO.File]::ReadAllText($path))|ConvertFrom-Json
  $owner=Get-Process -Id $data.ownerPid -ErrorAction Stop
  return $data.role -ceq $Role -and [DateTime]::Parse($data.expires).ToUniversalTime() -gt [DateTime]::UtcNow -and $owner.StartTime.ToUniversalTime().ToString('o') -ceq $data.ownerStarted
 }catch{return $false}
}
function Remove-AriaGrant {param([string]$Token) $path=Get-AriaGrantPath $Token;if($path -and (Test-Path -LiteralPath $path)){Assert-DreamSkinNoReparseComponents $path;[IO.File]::Delete($path)}}
function Lock-AriaHidden {Remove-AriaGrant $script:AriaHiddenToken;$script:AriaHiddenToken='';$script:AriaPrivacyChallenge=$null}
function Lock-AriaAdmin {Remove-AriaGrant $script:AriaAdminToken;$script:AriaAdminToken=''}
function Assert-AriaAttemptAllowed {if([DateTime]::UtcNow -lt $script:AriaPrivacyRetryAfter){throw '尝试次数较多，请稍等 30 秒再试。'}}
function Register-AriaFailedAttempt {$script:AriaPrivacyFailures++;if($script:AriaPrivacyFailures -ge 5){$script:AriaPrivacyRetryAfter=[DateTime]::UtcNow.AddSeconds(30);$script:AriaPrivacyFailures=0}}
function New-AriaPrivacyChallenge {
 Assert-AriaAttemptAllowed
 Lock-AriaHidden;$questions=@((Get-AriaPrivacyConfig).questions);if(-not $questions.Count){throw '问题库为空，请用管理员密码添加问题。'}
 $q=$questions[(Get-Random -Minimum 0 -Maximum $questions.Count)]
 $script:AriaPrivacyChallenge=[pscustomobject]@{id=[guid]::NewGuid().ToString('N');entry=$q;expires=[DateTime]::UtcNow.AddMinutes(3)}
 return [pscustomobject]@{challengeId=$script:AriaPrivacyChallenge.id;question=$q.question}
}
function Unlock-AriaHidden {
 param([string]$ChallengeId,[string]$Answer)
 Assert-AriaAttemptAllowed;if($Answer.Length -gt 64){throw '答案最多 64 字。'};$challenge=$script:AriaPrivacyChallenge
 if(-not $challenge -or $ChallengeId -cne $challenge.id -or [DateTime]::UtcNow -gt $challenge.expires){throw '问题已过期，请重新进入隐藏皮肤。'}
 if(-not[AriaPrivacyCrypto]::Verify($Answer,$challenge.entry.salt,$challenge.entry.hash)){Register-AriaFailedAttempt;throw '回答不正确，再想想吧。'}
 $script:AriaPrivacyFailures=0;$script:AriaHiddenToken=New-AriaGrant 'hidden';$script:AriaPrivacyChallenge=$null
}
function Unlock-AriaAdmin {
 param([string]$Password)
 Assert-AriaAttemptAllowed;if($Password.Length -gt 256){throw '密码过长。'};$auth=(Get-AriaPrivacyConfig).password
 if(-not[AriaPrivacyCrypto]::Verify($Password,$auth.salt,$auth.hash)){Register-AriaFailedAttempt;throw '管理员密码不正确。'}
 Lock-AriaAdmin;$script:AriaPrivacyFailures=0;$script:AriaAdminToken=New-AriaGrant 'admin'
}
function Get-AriaQuestionBank {
 if(-not(Test-AriaGrant -Role admin)){throw '请先验证管理员密码。'}
 return @((Get-AriaPrivacyConfig).questions|ForEach-Object {[pscustomobject]@{id=$_.id;question=$_.question}})
}
function Save-AriaQuestionBank {
 param([object[]]$Questions)
 if(-not(Test-AriaGrant -Role admin)){throw '请先验证管理员密码。'}
 if($Questions.Count -lt 1 -or $Questions.Count -gt 20){throw '问题库需要保留 1 至 20 个问题。'}
 $config=Get-AriaPrivacyConfig;$updated=@();$seen=@{}
 foreach($item in $Questions){
  $text=([string]$item.question).Trim();$answer=([string]$item.answer).Trim();$id=[string]$item.id
  if($text.Length -lt 2 -or $text.Length -gt 100 -or $answer.Length -gt 64){throw '问题需为 2 至 100 字，答案最多 64 字。'}
  $old=@($config.questions|Where-Object id -ceq $id)|Select-Object -First 1
  if($old -and -not $answer){$q=[pscustomobject]@{id=$old.id;question=$text;salt=$old.salt;hash=$old.hash}}
  else{if(-not $answer){throw '新问题需要填写答案。'};$salt=[AriaPrivacyCrypto]::Random();$q=[pscustomobject]@{id=[guid]::NewGuid().ToString('N');question=$text;salt=$salt;hash=[AriaPrivacyCrypto]::Hash($answer,$salt)}}
  if($seen.ContainsKey($text)){throw '请不要添加重复问题。'};$seen[$text]=$true;$updated+=@($q)
 }
 $config.questions=$updated;Write-AriaPrivacyConfig $config
 $script:AriaPrivacyChallenge=$null
}
function Assert-AriaThemeVisible {
 param([string]$Id)
 if(@(Get-AriaHiddenIds) -contains $Id -and -not(Test-AriaGrant -Role hidden)){throw '请先进入隐藏皮肤并回答验证问题。'}
}
function Set-AriaThemesHidden {
 param([string[]]$Ids,[bool]$Hidden)
 if(-not $Ids.Count -or $Ids.Count -gt 100){throw '请选择 1 至 100 张皮肤。'}
 $guard=Enter-DreamSkinOperationLock -TimeoutMilliseconds 5000
 try{
  $active=Read-DreamHubJson (Join-Path $script:DreamHubState 'active-theme\theme.json') $null
  foreach($id in $Ids){if($Hidden -and $id -ceq $active.id){throw '请先切换当前正在使用的皮肤，再隐藏它。'};$null=Get-DreamHubThemeById $id}
  $config=Get-AriaPrivacyConfig
  if($Hidden){$config.hiddenIds=@(@($config.hiddenIds)+$Ids|Select-Object -Unique)}else{$config.hiddenIds=@($config.hiddenIds|Where-Object {$_ -notin $Ids})}
  Write-AriaPrivacyConfig $config
 }finally{Exit-DreamSkinOperationLock $guard}
}
function Remove-AriaCancelledJobs {
 param([string[]]$Ids,[switch]$All)
 $guard=Enter-DreamSceneMutex 'Queue'
 if(-not $guard){throw '任务正忙，请稍后清理。'}
 try{
  $jobs=@(Get-DreamSceneJobs|Where-Object {-not $_.testOnly -and $_.status -eq 'cancelled'})
  if(-not $All){$jobs=@($jobs|Where-Object {$_.id -in $Ids});if($jobs.Count -ne @($Ids|Select-Object -Unique).Count){throw '只允许清理已取消的任务。'}}
  foreach($job in $jobs){
   $capture=Get-DreamSceneJobPath $job.id 'captures'
   foreach($path in @($capture,[IO.Path]::ChangeExtension($capture,'partial.mp4'),(Get-DreamSceneJobPath $job.id 'logs'),(Join-Path (Join-Path $script:DreamSceneQueueRoot 'logs') ($job.id+'.progress')),(Get-DreamSceneJobPath $job.id 'cancel'),(Get-DreamSceneJobPath $job.id))){
    Assert-DreamSkinNoReparseComponents $path
    if(-not(Test-DreamSkinPathWithin $path $script:DreamSceneQueueRoot)){throw '任务清理路径越界。'}
    if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
   }
  }
  return $jobs.Count
 }finally{Exit-DreamSceneMutex $guard}
}
