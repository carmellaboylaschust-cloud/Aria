param(
 [Parameter(Mandatory=$true)][string]$NodeDirectory,
 [Parameter(Mandatory=$true)][string]$WebView2Directory,
 [string]$FFmpegDirectory,
 [string]$WallpaperEngine,
 [switch]$AcceptLocalDebugging
)
$ErrorActionPreference='Stop'
if(-not $AcceptLocalDebugging){throw '请先阅读 SECURITY.md 的本机调试权限说明，确认后使用 -AcceptLocalDebugging 安装。'}
$source=Split-Path $PSScriptRoot -Parent
$target='D:\Aria'
. (Join-Path $source 'engine\scripts\release-security.ps1')
. (Join-Path $source 'engine\scripts\common-windows.ps1')
. (Join-Path $source 'engine\scripts\theme-windows.ps1')
if(Test-Path -LiteralPath $target){throw 'D:\Aria 已存在。请保留数据，并按安装文档执行升级检查。'}
foreach($path in @($source,$NodeDirectory,$WebView2Directory)) {Assert-DreamSkinNoReparseComponents $path}
$node=Join-Path $NodeDirectory 'node.exe'
$null=Get-DreamSkinValidatedNodeRuntime -Path $node
foreach($name in @('node.exe','LICENSE')) {if(-not(Test-Path -LiteralPath (Join-Path $NodeDirectory $name))){throw "请准备 Node.js 文件：$name"}}
foreach($name in @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')){
 $path=Join-Path $WebView2Directory $name
 if(-not(Test-Path -LiteralPath $path)){throw "请准备 WebView2 SDK 文件：$name"}
 $signature=Get-AuthenticodeSignature -LiteralPath $path
 if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){throw "请使用 Microsoft 签名的 WebView2 SDK 文件：$name"}
}
if($FFmpegDirectory){Assert-DreamSkinNoReparseComponents $FFmpegDirectory;foreach($name in @('ffmpeg.exe','ffprobe.exe')){if(-not(Test-Path -LiteralPath (Join-Path $FFmpegDirectory $name))){throw "请准备 FFmpeg 文件：$name"}}}
if($WallpaperEngine){Assert-DreamSkinNoReparseComponents $WallpaperEngine;if(-not(Test-Path -LiteralPath $WallpaperEngine -PathType Leaf) -or [IO.Path]::GetFileName($WallpaperEngine) -ine 'wallpaper64.exe'){throw '请选择 Steam 安装的 wallpaper64.exe。'}}
# Validate source trees before any recursive copy; symlinks/junctions are rejected.
function Assert-PlainTree([string]$Path){Assert-DreamSkinNoReparseComponents $Path;foreach($item in @(Get-ChildItem -LiteralPath $Path -Force)){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '源码目录中发现重解析点，请检查源码副本。'};if($item.PSIsContainer){Assert-PlainTree $item.FullName}}}
Assert-PlainTree (Join-Path $source 'engine')
New-AriaPrivateDirectory $target
foreach($part in @('runtime','user-backgrounds','user-backgrounds\temp','tools\webview2','tools\ffmpeg-9.0.2\bin')){[void][IO.Directory]::CreateDirectory((Join-Path $target $part))}
Copy-Item -LiteralPath (Join-Path $source 'engine') -Destination (Join-Path $target 'runtime\engine') -Recurse
$nodeOut=Join-Path $target 'runtime\engine\runtime\node';[void][IO.Directory]::CreateDirectory($nodeOut)
foreach($name in @('node.exe','LICENSE')){Copy-Item -LiteralPath (Join-Path $NodeDirectory $name) -Destination (Join-Path $nodeOut $name)}
foreach($name in @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')){Copy-Item -LiteralPath (Join-Path $WebView2Directory $name) -Destination (Join-Path $target ('tools\webview2\'+$name))}
if($FFmpegDirectory){
 $files=@{}
 foreach($name in @('ffmpeg.exe','ffprobe.exe')){$dest=Join-Path $target ('tools\ffmpeg-9.0.2\bin\'+$name);Copy-Item -LiteralPath (Join-Path $FFmpegDirectory $name) -Destination $dest;$files['bin/'+$name]=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash}
 @{files=$files;purpose='local integrity baseline'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $target 'tools\ffmpeg-9.0.2\verified.json') -Encoding UTF8
}
if($WallpaperEngine){@{wallpaperEngine=[IO.Path]::GetFullPath($WallpaperEngine)}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $target 'user-backgrounds\capture-settings.json') -Encoding UTF8}
'Local debugging access reviewed during installation.'|Set-Content -LiteralPath (Join-Path $target 'user-backgrounds\local-debugging-consent.txt') -Encoding UTF8
foreach($name in @('LICENSE','NOTICE.md','SECURITY.md','PRIVACY.md')){Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $target $name)}
Add-Type -AssemblyName System.Drawing
$bitmap=[Drawing.Bitmap]::new(64,64);$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{
 $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#CFEAF6'))
 $font=[Drawing.Font]::new('Segoe UI Symbol',36);$brush=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#5878A6'))
 try{$graphics.DrawString([string][char]0x266B,$font,$brush,8,6)}finally{$font.Dispose();$brush.Dispose()}
 $handle=$bitmap.GetHicon();$icon=[Drawing.Icon]::FromHandle($handle)
 $stream=[IO.File]::Create((Join-Path $target 'user-backgrounds\aria.ico'))
 try{$icon.Save($stream)}finally{$stream.Dispose();$icon.Dispose()}
}finally{$graphics.Dispose();$bitmap.Dispose()}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach($pair in @(@('AriaLauncher.cs','Aria.exe'),@('CodexLauncher.cs','Open-Codex.exe'))){
 & $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll (('/win32icon:'+(Join-Path $target 'user-backgrounds\aria.ico'))) (('/out:'+(Join-Path $target ('user-backgrounds\'+$pair[1])))) (Join-Path $source ('launcher\'+$pair[0]))
 if($LASTEXITCODE -ne 0){throw '启动器编译失败，请保留安装目录以便检查。'}
}
$null=Initialize-DreamSkinThemeStore -SkillRoot (Join-Path $target 'runtime\engine') -StateRoot (Join-Path $target 'runtime')
Assert-AriaPrivateDirectory $target
Write-Output 'Aria 已安装。打开 D:\Aria\user-backgrounds\Aria.exe，在偏好与存储中设置管理员。'
