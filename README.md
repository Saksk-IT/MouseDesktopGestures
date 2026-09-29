# 鼠标桌面手势 / Mouse Desktop Gestures

Windows 10/11 x64 免安装鼠标手势工具。按住鼠标侧键向左右滑动可切换虚拟桌面，向上滑动可打开任务视图。两个侧键可以分别设置动作；短按可保留原来的鼠标按键功能。

**当前版本：1.5.2。** 本仓库收录可直接运行的 EXE、默认 JSON 配置、AutoHotkey 源码、图标素材、构建说明，以及运行引擎的许可证和源码归档。用户自己的配置、日志和备份不包含在内。

## 使用

从 [Releases](https://github.com/Saksk-IT/MouseDesktopGestures/releases) 下载免安装 ZIP，解压后运行 `MouseDesktopGestures.exe`；发布页会标明 ZIP 的具体版本。双击托盘图标或再次运行 EXE 可打开设置；在设置里可调整手势、灵敏度、应用白名单、静默模式、开机启动，以及导入、导出或恢复配置。第一次使用桌面切换前，请在 Windows 中创建至少两个虚拟桌面。

也可以直接下载仓库内容运行其中的 EXE；它不需要单独安装 AutoHotkey。更详细的操作说明见 [使用说明.txt](使用说明.txt)。

## 项目文件

- [MouseDesktopGestures.exe](MouseDesktopGestures.exe)：Windows x64 免安装程序
- [config.default.json](config.default.json)：仓库中的默认配置；首次运行生成的 `config.json` 是个人配置，已被 Git 忽略
- [VERSION](VERSION)：版本号；构建脚本会检查源码、说明和 EXE 版本是否一致
- [source/MouseDesktopGestures.ahk](source/MouseDesktopGestures.ahk)、[source/UiTheme.ahk](source/UiTheme.ahk)、[source/Json.ahk](source/Json.ahk)：应用源代码
- [source/BUILD.txt](source/BUILD.txt)：构建命令、工具版本和自检方法
- [scripts/build.ps1](scripts/build.ps1)：固定工具版本，构建、自检、打包并生成 SHA-256 校验文件
- [assets](assets)：程序图标与原始图像
- [LICENSE](LICENSE)：应用源码许可证；[licenses](licenses)、[source/AutoHotkey-v2.0.28-source.zip](source/AutoHotkey-v2.0.28-source.zip)：运行引擎的授权文件与源码

应用源码采用 GPL-2.0-or-later；编译所用的 AutoHotkey 运行引擎依据其随包附带的 GPL-2.0 许可证分发。构建命令及具体版本见 `source/BUILD.txt`。

## 1.5.2 更新

- 损坏的 `config.json` 在下次保存时会隔离为带时间戳的 `.corrupt-*` 文件，已有的 `config.json.bak` 保持不变；正常保存会先验证临时文件，再使用 Windows 文件替换操作。
- 第二次启动会等待原进程初始化完成，再请求打开设置。开机启动快捷方式会校验目标、参数和工作目录；失效时在设置中提示，保存后修复。
- 无效的单个配置值会提示并恢复默认值；严重的 JSON 或结构错误会写入小容量 `logs/error.log`。Debug 日志改为定时批量写入，减少手势期间的磁盘等待。
- 默认配置与个人配置分离。构建脚本在独立目录打包，发布包中仍提供首次使用的 `config.json`；CI 在提交时构建并运行自检，版本标签通过验证后可自动发布。

## 作者

[Saksk-IT](https://github.com/Saksk-IT) · [GitHub 仓库](https://github.com/Saksk-IT/MouseDesktopGestures)
