# 鼠标桌面手势 / Mouse Desktop Gestures

Windows 10/11 x64 免安装鼠标手势工具。按住鼠标侧键向左右滑动可切换虚拟桌面，向上滑动可打开任务视图。两个侧键可以分别设置动作；短按可保留原来的鼠标按键功能。

**当前版本：1.4.1。** 本仓库收录这一版本的完整分享包：可直接运行的 EXE、默认 JSON 配置、AutoHotkey 源码、图标素材、构建说明，以及运行引擎的许可证和源码归档。用户自己的配置、日志和备份不包含在内。

## 使用

从 [Releases](https://github.com/Saksk-IT/MouseDesktopGestures/releases) 下载免安装 ZIP，解压后运行 `MouseDesktopGestures.exe`。双击托盘图标可打开设置；在设置里可调整手势、灵敏度、应用白名单、开机启动，以及导入、导出或恢复配置。第一次使用桌面切换前，请在 Windows 中创建至少两个虚拟桌面。

也可以直接下载仓库内容运行其中的 EXE；它不需要单独安装 AutoHotkey。更详细的操作说明见 [使用说明.txt](使用说明.txt)。

## 项目文件

- [MouseDesktopGestures.exe](MouseDesktopGestures.exe)：Windows x64 免安装程序
- [config.json](config.json)：默认配置，可在程序中修改
- [source/MouseDesktopGestures.ahk](source/MouseDesktopGestures.ahk)、[source/UiTheme.ahk](source/UiTheme.ahk)、[source/Json.ahk](source/Json.ahk)：应用源代码
- [source/BUILD.txt](source/BUILD.txt)：构建命令、工具版本和自检方法
- [assets](assets)：程序图标与原始图像
- [licenses](licenses)、[source/AutoHotkey-v2.0.28-source.zip](source/AutoHotkey-v2.0.28-source.zip)：运行引擎的授权文件与源码

应用源码采用 GPL-2.0-or-later；编译所用的 AutoHotkey 运行引擎依据其随包附带的 GPL-2.0 许可证分发。构建命令及具体版本见 `source/BUILD.txt`。
