param([string]$Root=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'engine\scripts\common-windows.ps1')
. (Join-Path $Root 'engine\scripts\theme-windows.ps1')
. (Join-Path $Root 'engine\scripts\release-security.ps1')
. (Join-Path $Root 'engine\scripts\hub-data.ps1')
$parent=Join-Path $Root '.test-output';[void][IO.Directory]::CreateDirectory($parent)
$fixture=Join-Path $parent ('acl-'+[guid]::NewGuid().ToString('N'))
New-AriaPrivateDirectory $fixture
Assert-AriaPrivateDirectory $fixture
$child=Join-Path $fixture 'inherited';[void][IO.Directory]::CreateDirectory($child)
Assert-AriaPrivateDirectory $child
$acl=Get-Acl -LiteralPath $child
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-11'),'ReadAndExecute','Allow'))
Set-Acl -LiteralPath $child -AclObject $acl
$blocked=$false;try{Assert-AriaPrivateDirectory $child}catch{$blocked=$true};if(-not $blocked){throw 'Broad ACL accepted'}
$script:DreamHubHome=$fixture;$script:DreamHubState=Join-Path $fixture 'runtime'
foreach($name in @('steam-profile\Cookies','privacy\vault.dat','browser-profile\Cookies','requests\private.json')){
 $private=Join-Path $fixture $name;[void][IO.Directory]::CreateDirectory((Split-Path $private -Parent));[IO.File]::WriteAllText($private,'synthetic fixture')
 $blocked=$false;try{$null=ConvertTo-DreamHubMediaUrl (Join-Path $fixture $name)}catch{$blocked=$true};if(-not $blocked){throw 'Private path accepted'}
}
$media=Join-Path $fixture 'themes\fixture\image.png';[void][IO.Directory]::CreateDirectory((Split-Path $media -Parent));[IO.File]::WriteAllText($media,'synthetic path fixture')
$url=ConvertTo-DreamHubMediaUrl $media
if($url -ne 'https://media0.skin.local/fixture/image.png'){throw 'Media URL mapping failed'}
Write-Output 'Directory ACL and private media boundary checks passed: 8'
