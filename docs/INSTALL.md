# 安装与构建

当前源码面向 Windows 11 x64，使用 Windows PowerShell 5.1、系统 .NET Framework 编译器、Node.js 22 或更新版本，以及 Microsoft WebView2。路径约定固定为 `D:\Aria`，便于将应用与用户资料集中到 D 盘。

## 准备依赖

1. 通过 Microsoft Store 安装适配的 `OpenAI.Codex` 桌面应用。
2. 从 Node.js 官方 Windows x64 发行包准备 `node.exe` 和 `LICENSE`，放入同一个目录。安装程序会检查数字签名与主版本。
3. 安装 WebView2 Evergreen Runtime。获取 Microsoft.Web.WebView2 正式 SDK，把 .NET Framework 兼容目录中的 `Microsoft.Web.WebView2.Core.dll`、`Microsoft.Web.WebView2.WinForms.dll` 和 x64 原生目录中的 `WebView2Loader.dll` 放入一个 SDK 目录。保留原包许可。
4. 视频元数据与转换功能需要 FFmpeg / ffprobe。根据 [FFmpeg 官方下载入口](https://ffmpeg.org/download.html) 选择可信 Windows 构建，核验发行者提供的校验信息，保留许可证。
5. Scene / Web 转换需要 Steam 安装的 Wallpaper Engine。记录其 `wallpaper64.exe` 完整路径。

## 本地安装

先阅读 `SECURITY.md`。在源码根目录打开 **Windows PowerShell 5.1**，替换下面示例中的依赖路径：

```powershell
.\tools\Install-Aria.ps1 `
  -NodeDirectory 'D:\Dependencies\node' `
  -WebView2Directory 'D:\Dependencies\webview2' `
  -FFmpegDirectory 'D:\Dependencies\ffmpeg\bin' `
  -WallpaperEngine 'D:\SteamLibrary\steamapps\common\wallpaper_engine\wallpaper64.exe' `
  -AcceptLocalDebugging
```

最后两个依赖参数可按所需功能选填。`-AcceptLocalDebugging` 表示安装者已经了解本机调试权限。安装脚本会创建独立目录、配置专用权限、复制代码和依赖、建立本地完整性清单、编译启动器，并准备原创默认皮肤。

运行 `D:\Aria\user-backgrounds\Aria.exe`。可为它创建快捷方式，名称使用 Aria。随后在「偏好与存储」设置管理员。

FFmpeg 哈希记录用于检测安装后的变化，其可信来源仍由下载与校验步骤确定。正式二进制发布应追加构建来源、完整依赖许可和代码签名流程。

## 升级与移除

安装脚本为新目录设计。升级前导出收藏，退出 Aria，并保存当前代码副本。按版本说明更新 `runtime/engine` 与启动器，随后校验目录权限。`user-backgrounds`、浏览器资料和隐私配置由使用者继续管理。

移除时先结束 Aria 与换肤桌面会话，将所需收藏导出，再通过资源管理器处理 `D:\Aria`。该操作会涉及保存在该目录的媒体和登录资料，请按个人保留需求选择内容。

## 验证

```powershell
powershell.exe -NoProfile -File .\tests\admin.ps1 -Root (Get-Location).Path
python .\tools\check-release.py
```

管理员页面测试使用 Playwright 和 Edge，可通过环境变量 `ARIA_PLAYWRIGHT_MODULE` 指定已安装的 Playwright 模块目录，再运行 `node tests/admin-ui.mjs engine/hub`。测试使用合成资料。
