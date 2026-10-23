function Get-DreamHubWindowSettings {
  $value=Read-DreamHubJson (Join-Path $script:DreamHubHome 'window-settings.json') $null
  if(-not $value -or $value.schemaVersion -ne 1){return [pscustomobject]@{schemaVersion=1;remember=$true;width=1370;height=960;state='normal'}}
  $width=1370;$height=960
  if($value.width -ge 1060 -and $value.width -le 5000){$width=[int]$value.width}
  if($value.height -ge 760 -and $value.height -le 3000){$height=[int]$value.height}
  return [pscustomobject]@{schemaVersion=1;remember=($value.remember -ne $false);width=$width;height=$height;state=$(if($value.state -eq 'maximized'){'maximized'}else{'normal'})}
}
function Set-DreamHubLogicalWindowSize {
  param([int]$Width,[int]$Height)
  $script:HubForm.WindowState='Normal'
  $dpi=[DreamHubDisplay]::GetDpiForWindow($script:HubForm.Handle);$scale=$dpi/96.0
  $work=[Windows.Forms.Screen]::FromHandle($script:HubForm.Handle).WorkingArea
  $w=[Math]::Min([int][Math]::Round($Width*$scale),$work.Width-[int][Math]::Round(24*$scale))
  $h=[Math]::Min([int][Math]::Round($Height*$scale),$work.Height-[int][Math]::Round(24*$scale))
  $script:HubForm.Size=[Drawing.Size]::new($w,$h)
  $script:HubForm.StartPosition='Manual'
  $script:HubForm.Location=[Drawing.Point]::new(($work.Left+[int](($work.Width-$script:HubForm.Width)/2)),($work.Top+[int](($work.Height-$script:HubForm.Height)/2)))
}
function Restore-DreamHubWindowSettings {
  $settings=Get-DreamHubWindowSettings
  if($settings.remember){
    Set-DreamHubLogicalWindowSize $settings.width $settings.height
    if($settings.state -eq 'maximized'){$script:HubForm.WindowState='Maximized'}
  }
}
function Save-DreamHubWindowSettings {
  if($script:HubForm.WindowState -eq 'Minimized'){return}
  $settings=Get-DreamHubWindowSettings
  $bounds=if($script:HubForm.WindowState -eq 'Normal'){$script:HubForm.Bounds}else{$script:HubForm.RestoreBounds}
  $scale=[DreamHubDisplay]::GetDpiForWindow($script:HubForm.Handle)/96.0
  if($scale -le 0){return}
  $settings.width=[Math]::Max(1060,[int][Math]::Round($bounds.Width/$scale))
  $settings.height=[Math]::Max(760,[int][Math]::Round($bounds.Height/$scale))
  $settings.state=if($script:HubForm.WindowState -eq 'Maximized'){'maximized'}else{'normal'}
  Write-DreamHubJson (Join-Path $script:DreamHubHome 'window-settings.json') $settings
  $script:NextData=[DateTime]::MinValue
}
function Set-DreamHubWindowPreset {
  param([ValidateSet('compact','standard','large','maximized')][string]$Preset)
  switch($Preset){
    'compact' {Set-DreamHubLogicalWindowSize 1100 780}
    'standard' {Set-DreamHubLogicalWindowSize 1370 960}
    'large' {Set-DreamHubLogicalWindowSize 1510 1000}
    'maximized' {$script:HubForm.WindowState='Maximized'}
  }
  Save-DreamHubWindowSettings
}
