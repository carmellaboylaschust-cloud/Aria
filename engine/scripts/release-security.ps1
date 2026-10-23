function Get-AriaAllowedSids {
 return @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
}
function Assert-AriaPrivateDirectory {
 param([Parameter(Mandatory=$true)][string]$Path)
 $full=[IO.Path]::GetFullPath($Path)
 $cursor=$full
 while($cursor){
  if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '请选择普通本地目录。'}}
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
 $acl=Get-Acl -LiteralPath $full
 $allowed=Get-AriaAllowedSids
 foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $allowed){throw 'Aria 目录权限需要收紧：请按安装文档设置为当前用户、SYSTEM 与 Administrators 专用。'}
 }
 if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $allowed){throw '请使用当前 Windows 用户拥有的安装目录。'}
}
function New-AriaPrivateDirectory {
 param([Parameter(Mandatory=$true)][string]$Path)
 $full=[IO.Path]::GetFullPath($Path)
 if(Test-Path -LiteralPath $full){throw '目标目录已存在，请选择独立的新目录。'}
 $cursor=[IO.Path]::GetDirectoryName($full)
 while($cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '请选择普通本地目录。'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetAccessRuleProtection($true,$false)
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $acl.SetOwner($sid)
 foreach($value in @(Get-AriaAllowedSids)){
  $identity=[Security.Principal.SecurityIdentifier]::new($value)
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
 }
 [IO.DirectoryInfo]::new($full).Create($acl)
 Assert-AriaPrivateDirectory $full
}
