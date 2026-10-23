# Explicit process, window and shortcut identities for the Aria shell host.
if(-not ('DreamAriaBrand' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class DreamAriaBrand {
 [StructLayout(LayoutKind.Sequential)] struct Key {public Guid fmtid;public uint pid;public Key(uint id){fmtid=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");pid=id;}}
 [StructLayout(LayoutKind.Explicit,Size=24)] struct Value {[FieldOffset(0)]public ushort vt;[FieldOffset(8)]public IntPtr text;}
 [ComImport,Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface Store {
  [PreserveSig]int GetCount(out uint count);
  [PreserveSig]int GetAt(uint index,out Key key);
  [PreserveSig]int GetValue(ref Key key,out Value value);
  [PreserveSig]int SetValue(ref Key key,ref Value value);
  [PreserveSig]int Commit();
 }
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)]public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
 [DllImport("shell32.dll")]static extern int SHGetPropertyStoreForWindow(IntPtr hwnd,ref Guid iid,[MarshalAs(UnmanagedType.Interface)]out Store store);
 [DllImport("ole32.dll")]static extern int PropVariantClear(ref Value value);
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)]static extern void SHChangeNotify(uint eventId,uint flags,string path1,IntPtr path2);
 static void Put(Store store,uint id,string text){
  var key=new Key(id);var value=new Value{vt=31,text=Marshal.StringToCoTaskMemUni(text)};
  try{Marshal.ThrowExceptionForHR(store.SetValue(ref key,ref value));}finally{PropVariantClear(ref value);}
 }
 static string Read(Store store,uint id){
  var key=new Key(id);Value value;Marshal.ThrowExceptionForHR(store.GetValue(ref key,out value));
  try{return value.vt==31?Marshal.PtrToStringUni(value.text):null;}finally{PropVariantClear(ref value);}
 }
 static Store WindowStore(IntPtr hwnd){
  Guid iid=typeof(Store).GUID;Store store;Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(hwnd,ref iid,out store));return store;
 }
 public static void SetWindow(IntPtr hwnd,string appId,string launcher,string icon){
  Store store=WindowStore(hwnd);
  try{
   // Supply the host window's own launch identity and icon before setting its grouping ID.
   Put(store,2,"\""+launcher+"\"");Put(store,4,"Aria");Put(store,3,icon+",0");Put(store,5,appId);
  }finally{Marshal.FinalReleaseComObject(store);}
 }
 public static string[] InspectWindow(IntPtr hwnd){
  Store store=WindowStore(hwnd);try{return new[]{Read(store,5),Read(store,2),Read(store,4),Read(store,3)};}finally{Marshal.FinalReleaseComObject(store);}
 }
 public static void SetShortcut(string path,string appId){
  object link=Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
  try{
   var file=(IPersistFile)link;file.Load(path,2);
   var store=(Store)link;Put(store,5,appId);Marshal.ThrowExceptionForHR(store.Commit());file.Save(path,true);
  }finally{Marshal.FinalReleaseComObject(link);}
  SHChangeNotify(0x00002000,0x0005,path,IntPtr.Zero);
 }
}
'@
}
function Initialize-DreamAriaBrand {param([string]$AppId) [Runtime.InteropServices.Marshal]::ThrowExceptionForHR([DreamAriaBrand]::SetCurrentProcessExplicitAppUserModelID($AppId))}
function Set-DreamAriaWindowBrand {param([IntPtr]$Handle) [DreamAriaBrand]::SetWindow($Handle,'Aria.SkinStudio','D:\Aria\user-backgrounds\Aria.exe','D:\Aria\user-backgrounds\aria.ico')}
