function Test-AriaPublicMediaUri {
 param([string]$Value,[switch]$Resolve)
 $u=$null
 if(-not[Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$u) -or $u.Scheme -cne 'https' -or $u.UserInfo -or $Value.Length -gt 4096 -or $u.IsLoopback){return $false}
 $h=$u.DnsSafeHost.TrimEnd('.').ToLowerInvariant()
 if(-not $h.Contains('.') -or $h -in @('0.0.0.0','localhost') -or $h.EndsWith('.local') -or $h.EndsWith('.localhost') -or $h.EndsWith('.internal')){return $false}
 $ips=@();$literal=$null
 if([Net.IPAddress]::TryParse($h,[ref]$literal)){$ips=@($literal)}
 elseif($Resolve){try{$ips=@([Net.Dns]::GetHostAddresses($h))}catch{return $false};if(-not $ips.Count){return $false}}
 foreach($ip in $ips){
  if($ip.IsIPv4MappedToIPv6){$ip=$ip.MapToIPv4()}
  if([Net.IPAddress]::IsLoopback($ip)){return $false}
  $v=$ip.GetAddressBytes()
  if($v.Length -eq 4){
   if($v[0] -in @(0,10,127) -or ($v[0] -eq 169 -and $v[1] -eq 254) -or ($v[0] -eq 172 -and $v[1] -ge 16 -and $v[1] -le 31) -or ($v[0] -eq 192 -and $v[1] -eq 168) -or ($v[0] -eq 100 -and $v[1] -ge 64 -and $v[1] -le 127) -or $v[0] -ge 224){return $false}
  }elseif($v.Length -eq 16){if($ip.IsIPv6LinkLocal -or $ip.IsIPv6Multicast -or $ip.IsIPv6SiteLocal -or ($v[0] -band 254) -eq 252 -or $ip.Equals([Net.IPAddress]::IPv6Any)){return $false}}
 }
 return $true
}
function Import-AriaWuwaDownload {
 param([string]$Path,[string]$Title,[string]$SourcePage)
 $root=Join-Path $script:DreamHubHome 'wuwa-downloads'
 if(-not(Test-DreamSkinThemePathWithin $Path $root)){throw '下载路径不在 D 盘应用目录。'}
 Assert-DreamSkinNoReparseComponents $Path
 $ext=[IO.Path]::GetExtension($Path).ToLowerInvariant()
 if($ext -notin @('.jpg','.jpeg','.png','.webp','.gif')){throw '此格式不会自动加入皮肤库。'}
 Assert-DreamHubMediaPolicy $Path;$null=Assert-DreamSkinImageFile $Path
 $saved=Join-Path $script:DreamHubHome 'saved-wallpapers';Assert-DreamSkinNoReparseComponents $saved;[void][IO.Directory]::CreateDirectory($saved)
 $hash=(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant();$to=Join-Path $saved ('wuwa-'+$hash.Substring(0,16)+$ext)
 Assert-DreamSkinNoReparseComponents $to
 if(Test-Path -LiteralPath $to){if((Get-FileHash -LiteralPath $to).Hash.ToLowerInvariant() -cne $hash){throw '已保存的文件内容不同，已保留两个文件，请手动检查。'}}
 else{[IO.File]::Copy($Path,$to)}
 $import=Import-DreamSkinLocalMedia $to
 $hidden=$import.Theme.id -in @(Get-AriaHiddenIds)
 if($hidden -and -not(Test-AriaGrant -Role hidden)){return [pscustomobject]@{themeId='';message='图片已保存到我的壁纸；隐藏列表中已有副本，可解锁后管理。'}}
 $name=([string]$Title).Trim();if(-not $name){$name='鸣潮壁纸'};if($name.Length -gt 70){$name=$name.Substring(0,70)}
 if(-not $import.AlreadyExists){$import.Theme.name=$name;Write-DreamSkinTheme $import.Directory $import.Theme}
 if($SourcePage -and (Test-AriaPublicMediaUri $SourcePage)){Write-DreamHubJson ($to+'.source.json') @{title=$name;sourcePage=([string]$SourcePage -split '\?')[0];savedAt=[DateTime]::UtcNow.ToString('o')}}
 return [pscustomobject]@{themeId=$import.Theme.id;message=if($import.AlreadyExists){'图片已保存，皮肤库中已有相同图片，无需重复添加'}else{'已保存到 D 盘我的壁纸，并加入我的皮肤'}}
}
function Save-AriaWuwaImage {
 param([string]$Url,[string]$Title,[string]$SourcePage)
 if(-not(Test-AriaPublicMediaUri $Url -Resolve)){throw '不支持此图片地址。'}
 $temp=Join-Path $script:DreamHubHome 'wuwa-downloads';Assert-DreamSkinNoReparseComponents $temp;[void][IO.Directory]::CreateDirectory($temp)
 $scratch=Join-Path $temp ([guid]::NewGuid().ToString('N')+'.part');$download=$null
 try{
  $uri=[Uri]$Url;$response=$null
  for($redirect=0;$redirect -le 4;$redirect++){
   if(-not(Test-AriaPublicMediaUri $uri.AbsoluteUri -Resolve)){throw '不支持重定向后的图片地址。'}
   $request=[Net.HttpWebRequest]::Create($uri);$request.Method='GET';$request.AllowAutoRedirect=$false;$request.UserAgent='Mozilla/5.0';$request.Referer='https://wuwa.games/';$request.Timeout=20000;$request.ReadWriteTimeout=20000
   $response=$request.GetResponse()
   if([int]$response.StatusCode -notin @(301,302,303,307,308)){break}
   $next=$response.Headers['Location'];$response.Dispose();$response=$null
   if(-not $next -or $redirect -eq 4){throw '图片地址重定向过多，请使用站内下载。'}
   $uri=[Uri]::new($uri,$next)
  }
  try{
   $ext=switch(($response.ContentType -split ';')[0].ToLowerInvariant()){'image/jpeg'{'.jpg'}'image/png'{'.png'}'image/webp'{'.webp'}'image/gif'{'.gif'}default{throw '此地址没有返回可保存的图片，请使用网页提供的原图下载。'}}
   if($response.ContentLength -gt 32MB){throw '图片超过 32 MB，已跳过保存。'}
   $stream=$response.GetResponseStream();$file=[IO.File]::Create($scratch)
   try{$buffer=New-Object byte[] 65536;[long]$total=0;while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){$total+=$read;if($total -gt 32MB){throw '图片超过 32 MB，已停止下载。'};$file.Write($buffer,0,$read)}}finally{$file.Dispose();$stream.Dispose()}
  }finally{if($response){$response.Dispose()}}
  $download=[IO.Path]::ChangeExtension($scratch,$ext.TrimStart('.'));[IO.File]::Move($scratch,$download)
  return Import-AriaWuwaDownload -Path $download -Title $Title -SourcePage $SourcePage
 }catch [Net.WebException]{throw '这张图片需要使用网页提供的下载入口。点击站内原图下载后，Aria 会接收并检查图片。'}
 finally{foreach($p in @($scratch,$download)){if($p -and (Test-Path -LiteralPath $p)){Assert-DreamSkinNoReparseComponents $p;[IO.File]::Delete($p)}}}
}
