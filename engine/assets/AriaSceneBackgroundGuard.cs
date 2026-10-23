
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public sealed class AriaSceneBackgroundGuard : IDisposable {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll")] static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hwnd,int n);
 [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hwnd,int n,IntPtr v);
 [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
 [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
 readonly string title,directory; readonly ManualResetEvent stop=new ManualResetEvent(false);readonly Thread thread;
 public int X{get;private set;}public int Y{get;private set;}public bool Observed{get;private set;}public bool ForegroundObserved{get;private set;}
 public bool IsOffscreen{get;private set;}public bool TaskbarSuppressed{get;private set;}public bool Minimized{get;private set;}
 public AriaSceneBackgroundGuard(string title,string directory){
  if(!System.Text.RegularExpressions.Regex.IsMatch(title,@"^(?:AriaCapture|CodexScene)-[a-f0-9]{32}$"))throw new ArgumentException("Invalid owned capture title");
  this.title=title;this.directory=Path.GetFullPath(directory).TrimEnd('\\');
  try{SetProcessDpiAwarenessContext(new IntPtr(-4));}catch(EntryPointNotFoundException){}
  X=GetSystemMetrics(76)+GetSystemMetrics(78)+128;Y=GetSystemMetrics(77)+64;
  thread=new Thread(Run);thread.IsBackground=true;thread.Name="Aria background capture window";thread.Start();
 }
 void Run(){IntPtr verified=IntPtr.Zero;uint verifiedPid=0;while(!stop.WaitOne(20)){try{
  IntPtr h=FindWindow(null,title);if(h==IntPtr.Zero)continue;
  uint pid;GetWindowThreadProcessId(h,out pid);
  if(h!=verified||pid!=verifiedPid){using(Process p=Process.GetProcessById((int)pid)){
   string executable=p.MainModule.FileName;
   string name=Path.GetFileName(executable);
   string parent=Path.GetDirectoryName(executable);
   bool main=String.Equals(parent,directory,StringComparison.OrdinalIgnoreCase)&&(String.Equals(name,"wallpaper64.exe",StringComparison.OrdinalIgnoreCase)||String.Equals(name,"wallpaper32.exe",StringComparison.OrdinalIgnoreCase));
   bool web=String.Equals(parent,Path.Combine(directory,"bin"),StringComparison.OrdinalIgnoreCase)&&(String.Equals(name,"webwallpaper32.exe",StringComparison.OrdinalIgnoreCase)||String.Equals(name,"webwallpaper64.exe",StringComparison.OrdinalIgnoreCase)||String.Equals(name,"edgewallpaper32.exe",StringComparison.OrdinalIgnoreCase)||String.Equals(name,"edgewallpaper64.exe",StringComparison.OrdinalIgnoreCase));
   if(!main&&!web)continue;
  }
  verified=h;verifiedPid=pid;}
  Observed=true;if(GetForegroundWindow()==h)ForegroundObserved=true;
  long style=GetWindowLongPtr(h,-20).ToInt64(),desired=(style|0x08000080L)&~0x00040000L;
  if(style!=desired)SetWindowLongPtr(h,-20,new IntPtr(desired));
  Rect r;GetWindowRect(h,out r);
  if(style!=desired||r.Left!=X||r.Top!=Y)SetWindowPos(h,new IntPtr(1),X,Y,0,0,0x0001|0x0010|0x0020|0x0200|0x4000);
  GetWindowRect(h,out r);int left=GetSystemMetrics(76),top=GetSystemMetrics(77),right=left+GetSystemMetrics(78),bottom=top+GetSystemMetrics(79);
  IsOffscreen=r.Right<=left||r.Left>=right||r.Bottom<=top||r.Top>=bottom;
  TaskbarSuppressed=(GetWindowLongPtr(h,-20).ToInt64()&0x80L)!=0;Minimized=IsIconic(h);
 }catch{}}}
 public void Dispose(){stop.Set();thread.Join(2000);stop.Dispose();}
}
