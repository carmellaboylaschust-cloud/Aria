$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
$dailyTemp='D:\Aria\user-backgrounds\temp';[void][IO.Directory]::CreateDirectory($dailyTemp);$env:TEMP=$dailyTemp;$env:TMP=$dailyTemp
$mutex=[Threading.Mutex]::new($false,('Local\Aria.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value+'.DailyWallpapers'))
try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true}
if(-not $owns){$mutex.Dispose();exit 0}
try{
 $node=Get-DreamSkinNodeRuntime
 $run=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList @((Join-Path $PSScriptRoot 'daily-wallpapers.mjs'),'--worker') -SeparateStderr
 if($run.ExitCode -ne 0){[IO.File]::AppendAllText('D:\Aria\user-backgrounds\daily-wallpapers-worker.log',($run.ErrorOutput -join [Environment]::NewLine),[Text.Encoding]::UTF8)}
}finally{if($owns){$mutex.ReleaseMutex()};$mutex.Dispose()}
