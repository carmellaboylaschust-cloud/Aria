param([switch]$ValidateOnly,[string]$PreviewImagePath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'scene-queue.ps1')
Initialize-DreamSceneQueue
if($ValidateOnly){@(Get-DreamSceneJobs)|ConvertTo-Json -Depth 8;exit 0}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=[Windows.Forms.Form]::new()
$form.Text='1080p 场景任务列表';$form.Width=960;$form.Height=590
$form.StartPosition='CenterScreen';$form.MinimumSize=[Drawing.Size]::new(960,590)
$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
try{$form.Icon=[Drawing.Icon]::new('D:\Aria\user-backgrounds\codex.ico')}catch{}
$intro=[Windows.Forms.Label]::new()
$intro.Text='任务会依次自动录制；关闭此列表后仍在后台继续，完成后自动加入皮肤库。'
$intro.SetBounds(20,15,900,28);$form.Controls.Add($intro)
$hint=[Windows.Forms.Label]::new()
$hint.Text='1920 × 1080 · 30 帧/秒 · 静音。录制时请保持电脑解锁，场景窗口可遮挡，请勿关闭或最小化。'
$hint.SetBounds(20,45,900,28);$form.Controls.Add($hint)
$script:jobsView=[Windows.Forms.ListView]::new()
$script:jobsView.SetBounds(20,88,905,310)
$script:jobsView.View='Details';$script:jobsView.FullRowSelect=$true;$script:jobsView.MultiSelect=$false
$script:jobsView.HideSelection=$false;$script:jobsView.ShowItemToolTips=$true
foreach($column in @(@('场景',270),@('状态',90),@('进度',75),@('时长',65),@('说明',375))){[void]$script:jobsView.Columns.Add([string]$column[0],[int]$column[1])}
$form.Controls.Add($script:jobsView)
$script:queueDetail=[Windows.Forms.Label]::new();$script:queueDetail.SetBounds(20,410,905,50)
$form.Controls.Add($script:queueDetail)
$duration=[Windows.Forms.ComboBox]::new();$duration.DropDownStyle='DropDownList'
foreach($n in @(10,20,30,60)){[void]$duration.Items.Add("$n 秒")};$duration.SelectedIndex=1
$duration.SetBounds(20,478,100,30);$form.Controls.Add($duration)
$add=[Windows.Forms.Button]::new();$add.Text='添加场景任务…';$add.SetBounds(130,474,155,36);$form.Controls.Add($add)
$cancel=[Windows.Forms.Button]::new();$cancel.Text='取消选中任务';$cancel.SetBounds(305,474,145,36);$form.Controls.Add($cancel)
$retry=[Windows.Forms.Button]::new();$retry.Text='重试';$retry.SetBounds(465,474,90,36);$form.Controls.Add($retry)
$open=[Windows.Forms.Button]::new();$open.Text='查看视频';$open.SetBounds(570,474,120,36);$form.Controls.Add($open)
$close=[Windows.Forms.Button]::new();$close.Text='关闭列表';$close.SetBounds(790,474,135,36);$form.Controls.Add($close)
$script:queueSignature=''
function Get-SelectedSceneJob {
  if($script:jobsView.SelectedItems.Count){return $script:jobsView.SelectedItems[0].Tag}
  return $null
}
function Update-SceneQueueView {
  $all=@(Get-DreamSceneJobs)
  $signature=($all|ForEach-Object {$_.id+$_.updatedAt})-join '|'
  if($signature -ceq $script:queueSignature){return}
  $script:queueSignature=$signature
  $selected=Get-SelectedSceneJob
  $script:jobsView.BeginUpdate();$script:jobsView.Items.Clear()
  $labels=@{queued='等待中';starting='准备中';recording='录制中';finalizing='处理中';completed='已完成';failed='失败';cancelled='已取消'}
  foreach($job in $all){
    $item=[Windows.Forms.ListViewItem]::new([string]$job.name)
    [void]$item.SubItems.Add([string]$labels[$job.status]);[void]$item.SubItems.Add("$($job.percent)%")
    [void]$item.SubItems.Add("$($job.seconds) 秒");[void]$item.SubItems.Add([string]$job.message)
    $item.Tag=$job;$item.ToolTipText=$job.message
    [void]$script:jobsView.Items.Add($item)
    if($selected -and $selected.id -ceq $job.id){$item.Selected=$true}
  }
  $script:jobsView.EndUpdate()
  $busy=@($all|Where-Object {$_.status -in @('queued','starting','recording','finalizing')}).Count
  $done=@($all|Where-Object {$_.status -eq 'completed'}).Count
  $script:queueDetail.Text="待完成 $busy 个 · 已完成 $done 个。录制不会自动切换你当前使用的背景。"
}
$script:jobsView.add_SelectedIndexChanged({
  $job=Get-SelectedSceneJob
  $cancel.Enabled=$job -and $job.status -in @('queued','starting','recording')
  $retry.Enabled=$job -and $job.status -in @('failed','cancelled')
  $open.Enabled=$job -and $job.status -eq 'completed'
  if($job){$script:queueDetail.Text=$job.message}
})
$add.add_Click({
  $dialog=[Windows.Forms.OpenFileDialog]::new()
  $dialog.Title='选择已下载场景的 project.json'
  $dialog.Filter='Wallpaper Engine 场景|project.json'
  $dialog.InitialDirectory='D:\'
  try{
    if($dialog.ShowDialog($form) -eq 'OK'){
      $seconds=@(10,20,30,60)[$duration.SelectedIndex]
      $null=Add-DreamSceneJob -ProjectPath $dialog.FileName -Seconds $seconds
      Update-SceneQueueView
    }
  }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'无法添加任务')}
  finally{$dialog.Dispose()}
})
$cancel.add_Click({try{$job=Get-SelectedSceneJob;if($job){Stop-DreamSceneJob $job.id;$script:queueDetail.Text='已请求取消，正在收尾…'}}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'取消失败')}})
$retry.add_Click({try{$job=Get-SelectedSceneJob;if($job){$null=Add-DreamSceneJob -ProjectPath $job.projectPath -Seconds $job.seconds -Appearance $job.appearance;Update-SceneQueueView}}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'重试失败')}})
$open.add_Click({try{$job=Get-SelectedSceneJob;if($job -and $job.outputPath){Start-Process -FilePath $job.outputPath}}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'无法打开视频')}})
$close.add_Click({$form.Close()})
$timer=[Windows.Forms.Timer]::new();$timer.Interval=1000
$timer.add_Tick({try{Update-SceneQueueView}catch{$script:queueDetail.Text='暂时无法读取进度，将自动重试。'}})
$form.add_Shown({$timer.Start()})
Update-SceneQueueView
if($PreviewImagePath){
  $form.ShowInTaskbar=$false;$form.Opacity=0;$form.Show();[Windows.Forms.Application]::DoEvents()
  $bmp=[Drawing.Bitmap]::new($form.Width,$form.Height)
  try{$form.DrawToBitmap($bmp,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bmp.Save($PreviewImagePath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bmp.Dispose()}
}else{[void]$form.ShowDialog()}
$timer.Stop();$timer.Dispose();$form.Dispose()
