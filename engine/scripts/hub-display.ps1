# Native-pixel rendering for the Dream Hub window. No system-wide settings are changed.
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
if(-not ('DreamHubDisplay' -as [type])){
Add-Type -ReferencedAssemblies @('System.Windows.Forms','System.Drawing') -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class DreamHubDisplay {
    [DllImport("user32.dll", SetLastError=true)] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowDpiAwarenessContext(IntPtr window);
    [DllImport("user32.dll")] private static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
    public static void Initialize() {
        // PowerShell may have already selected its process-wide mode. Its GUI
        // thread can still create all our windows in Per-Monitor V2 mode.
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        if (SetThreadDpiAwarenessContext(new IntPtr(-4)) == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot enable native-resolution rendering.");
    }
    public static bool IsPerMonitorV2(IntPtr window) {
        return AreDpiAwarenessContextsEqual(GetWindowDpiAwarenessContext(window), new IntPtr(-4));
    }
}
public class DreamHubWindow : Form {
    private const int WmDpiChanged = 0x02E0;
    private readonly Size logicalMinimum = new Size(1060,760);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left,Top,Right,Bottom; }
    public DreamHubWindow() {
        // The page handles layout in CSS pixels. Size the native host once in
        // physical pixels, rather than allowing WinForms to scale it twice.
        AutoScaleMode = AutoScaleMode.None;
    }
    private int Pixels(int logical, uint dpi) {
        return (int)Math.Round(logical * Math.Max(96u,dpi) / 96.0);
    }
    private void SetMinimumForDpi(uint dpi, Rectangle work) {
        MinimumSize = new Size(
            Math.Min(Pixels(logicalMinimum.Width,dpi), Math.Max(640,work.Width-Pixels(24,dpi))),
            Math.Min(Pixels(logicalMinimum.Height,dpi), Math.Max(480,work.Height-Pixels(24,dpi))));
    }
    public void FitInitialDisplay() {
        uint dpi=DreamHubDisplay.GetDpiForWindow(Handle);
        Rectangle work=Screen.FromHandle(Handle).WorkingArea;
        SetMinimumForDpi(dpi,work);
        Size=new Size(Math.Min(Pixels(1370,dpi),work.Width-Pixels(24,dpi)),
                      Math.Min(Pixels(960,dpi),work.Height-Pixels(24,dpi)));
        StartPosition=FormStartPosition.Manual;
        Location=new Point(work.Left+(work.Width-Width)/2,work.Top+(work.Height-Height)/2);
    }
    protected override void WndProc(ref Message message) {
        if(message.Msg==WmDpiChanged) {
            NativeRect rect=(NativeRect)Marshal.PtrToStructure(message.LParam,typeof(NativeRect));
            uint dpi=(uint)(message.WParam.ToInt64() & 0xffff);
            base.WndProc(ref message);
            SetMinimumForDpi(dpi,Screen.FromHandle(Handle).WorkingArea);
            Bounds=Rectangle.FromLTRB(rect.Left,rect.Top,rect.Right,rect.Bottom);
            return;
        }
        base.WndProc(ref message);
    }
}
'@
}
