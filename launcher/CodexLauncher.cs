using System;using System.Diagnostics;using System.IO;using System.Reflection;using System.Windows.Forms;
[assembly:AssemblyTitle("Codex")][assembly:AssemblyDescription("Codex desktop launcher for Aria skins")][assembly:AssemblyProduct("Codex launcher")][assembly:AssemblyVersion("1.1.0.0")]
internal static class CodexLauncher{
 [STAThread]static void Main(){
  try{
   string script=@"D:\Aria\runtime\engine\scripts\launch-desktop.ps1";
   if(!File.Exists(script))throw new FileNotFoundException("找不到启动文件，请打开 Aria 检查 D 盘应用目录。");
   var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe"));
   info.Arguments="-NoProfile -STA -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \""+script+"\"";info.UseShellExecute=false;info.CreateNoWindow=true;info.WindowStyle=ProcessWindowStyle.Hidden;info.WorkingDirectory=@"D:\Aria\user-backgrounds";info.EnvironmentVariables["TEMP"]=@"D:\Aria\user-backgrounds\temp";info.EnvironmentVariables["TMP"]=info.EnvironmentVariables["TEMP"];using(var p=Process.Start(info)){}
  }catch(Exception e){MessageBox.Show(e.Message,"Codex",MessageBoxButtons.OK,MessageBoxIcon.Information);}
 }
}