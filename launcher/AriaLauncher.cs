using System;using System.Diagnostics;using System.IO;using System.Reflection;using System.Windows.Forms;
[assembly:AssemblyTitle("Aria")]
[assembly:AssemblyDescription("Aria Skin Studio")]
[assembly:AssemblyProduct("Aria · Aria")]
[assembly:AssemblyVersion("1.0.0.0")]
internal static class AriaLauncher{
 [STAThread] static void Main(string[] args){
  try{
   bool daily=Array.IndexOf(args,"--daily-worker")>=0;
   string script=@"D:\Aria\runtime\engine\scripts\"+(daily?"daily-wallpapers-worker.ps1":"skin-hub.ps1");
   if(!File.Exists(script))throw new FileNotFoundException("找不到应用文件，请检查 D 盘目录。");
   var info=new ProcessStartInfo();
   info.FileName=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe");
   info.Arguments="-NoProfile -STA -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \""+script+"\"";
   if(!daily&&Array.IndexOf(args,"--test-mode")>=0)info.Arguments+=" -TestMode";
   info.UseShellExecute=false;info.CreateNoWindow=true;info.WindowStyle=ProcessWindowStyle.Hidden;
   info.WorkingDirectory=@"D:\Aria\user-backgrounds";
   info.EnvironmentVariables["TEMP"]=@"D:\Aria\user-backgrounds\temp";
   info.EnvironmentVariables["TMP"]=info.EnvironmentVariables["TEMP"];
   using(var child=Process.Start(info)){}
  }catch(Exception e){if(Array.IndexOf(args,"--daily-worker")<0)MessageBox.Show(e.Message,"Aria",MessageBoxButtons.OK,MessageBoxIcon.Information);}
 }
}