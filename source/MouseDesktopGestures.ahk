#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off
#Include Json.ahk
#Include UiTheme.ahk
;@Ahk2Exe-SetName 鼠标桌面手势
;@Ahk2Exe-SetDescription 带方向锁定、按键检测和应用白名单的鼠标手势
;@Ahk2Exe-SetVersion 1.5.1
;@Ahk2Exe-SetMainIcon ..\assets\app.ico

CoordMode "Mouse", "Screen"
Persistent
ActionIds := ["none", "desktop_left", "desktop_right", "task_view", "show_desktop", "next_window", "maximize"]
ActionLabels := ["无操作", "切到左侧桌面", "切到右侧桌面", "打开任务视图", "显示／恢复桌面", "切换到下一窗口", "最大化／还原窗口"]
TestMode := A_Args.Length && A_Args[1] = "--self-test"
LaunchMode := A_Args.Length ? A_Args[1] : "--settings"
InstanceMutex := 0
if !TestMode && !ClaimInstance(LaunchMode)
    ExitApp()
OnMessage(0x802B, ReceiveLaunchRequest)
BaseDir := A_ScriptDir
SplitPath (A_IsCompiled ? A_ScriptFullPath : A_AhkPath), &SelfExe
SelfExe := StrLower(SelfExe)
ConfigPath := BaseDir "\config.json"
LegacyPath := BaseDir "\config.ini"
StartupPath := A_Startup "\MouseDesktopGestures.lnk"
Paused := false, Busy := false, Detecting := false, Generation := 0
SettingsGui := 0, DetectorGui := 0, LastActionAt := -100000
AboutGui := 0
AuthorUrl := "https://github.com/Saksk-IT"
RepositoryUrl := "https://github.com/Saksk-IT/MouseDesktopGestures"
IconResource := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\..\assets\app.ico"
if FileExist(IconResource)
    TraySetIcon IconResource, 1, true
DraftApps := [], LastExternalApp := "", ContextText := "", LogFailed := false
AppliedContext := ""
DetectionKeys := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
ConfigWarning := ""
if TestMode
{
    BaseDir := A_Args.Length >= 2 ? A_Args[2] : A_Temp "\MouseDesktopGestures-test-" DllCall("GetCurrentProcessId")
    DirCreate BaseDir
    ConfigPath := BaseDir "\config.json"
    LegacyPath := BaseDir "\config.ini"
    StartupPath := BaseDir "\startup-test.lnk"
}
try Config := LoadConfig(ConfigPath, LegacyPath)
catch as err
{
    Config := Defaults()
    ConfigWarning := "JSON 配置读取失败，暂用默认设置。原文件保留；保存前请先修正或备份。`n" err.Message
}
if !TestMode
    MigrateStartupShortcut()

A_TrayMenu.Delete()
A_TrayMenu.Add("设置", ShowSettings)
A_TrayMenu.Add("鼠标按键检测", ShowDetector)
A_TrayMenu.Add("Debug 日志", ToggleDebug)
A_TrayMenu.Add("打开日志目录", OpenLogs)
A_TrayMenu.Add("暂停手势", TogglePause)
A_TrayMenu.Add("开机启动", ToggleStartup)
A_TrayMenu.Add("静默模式", ToggleSilentMode)
A_TrayMenu.Add("使用说明", ShowHelp)
A_TrayMenu.Add("关于", ShowAbout)
A_TrayMenu.Add()
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Default := "设置"
RegisterDetection()
ApplyConfig()
RefreshTray()
if TestMode
{
    try
    {
        RunSelfTest()
        FileAppend "compiled=" A_IsCompiled "; json_migration_lock_detector_logs_exclusions_gui_transfer_about=ok", "*"
        ExitApp 0
    }
    catch as err
    {
        FileAppend err.Message "`n" err.Stack, "**"
        ExitApp 1
    }
}
if !FileExist(ConfigPath)
{
    try WriteConfig(ConfigPath, Config)
    catch as err
        ConfigWarning := "无法保存配置，请把程序移到可写入的文件夹。`n" err.Message
}
Log("startup", "version=1.5.1")
if ConfigWarning != ""
    TrayTip ConfigWarning, "鼠标桌面手势 · 配置提示", "Icon!"
SetTimer UpdateContext, 50
if LaunchMode = "--settings"
    ShowSettings()
else if LaunchMode = "--detect"
    ShowDetector()
else if LaunchMode = "--about"
    ShowAbout()

ClaimInstance(mode)
{
    global InstanceMutex
    hash := 0
    Loop Parse, StrLower(A_ScriptFullPath)
        hash := (hash * 131 + Ord(A_LoopField)) & 0xFFFFFFFF
    name := "Local\MouseDesktopGestures-" Format("{:08X}", hash)
    Loop 40
    {
        handle := DllCall("kernel32\CreateMutexW", "Ptr", 0, "Int", 0, "Str", name, "Ptr")
        if !handle
            throw OSError(A_LastError, "CreateMutexW")
        already := A_LastError = 183
        if !already
        {
            InstanceMutex := handle
            return true
        }
        DllCall("kernel32\CloseHandle", "Ptr", handle)
        DetectHiddenWindows true
        for hwnd in WinGetList("ahk_class AutoHotkey")
        {
            if WinGetPID(hwnd) != DllCall("GetCurrentProcessId")
                && StrLower(WinGetTitle(hwnd)) = StrLower(A_ScriptFullPath)
            {
                request := mode = "--startup" ? 0 : mode = "--detect" ? 2 : mode = "--about" ? 3 : 1
                PostMessage 0x802B, request, 0, hwnd
                return false
            }
        }
        Sleep 50
    }
    MsgBox "程序已在启动中，请稍后再试。", "鼠标桌面手势", "Icon!"
    return false
}

ReceiveLaunchRequest(request, *)
{
    if request = 1
        SetTimer ShowSettings, -1
    else if request = 2
        SetTimer ShowDetector, -1
    else if request = 3
        SetTimer ShowAbout, -1
    return true
}

MigrateStartupShortcut()
{
    global ConfigWarning, StartupPath
    if !FileExist(StartupPath)
        return
    try
    {
        FileGetShortcut StartupPath, &target, &workingDir, &arguments
        if A_IsCompiled && StrLower(target) = StrLower(A_ScriptFullPath) && arguments = ""
            SetStartup(true)
    }
    catch as err
        ConfigWarning .= "`n无法更新开机启动快捷方式：" err.Message
}

Defaults()
{
    cfg := Map("SchemaVersion", 2, "Threshold", 80, "ShortClickMs", 350, "LockMs", 40,
        "AxisRatio", 135, "DebounceMs", 180, "Debug", 0, "SilentMode", 0, "ExcludedApps", [])
    for button in ["XButton1", "XButton2"]
        cfg[button] := Map("Enabled", 1, "ShortClick", 1, "Left", "desktop_right", "Right", "desktop_left", "Up", "task_view", "Down", "none")
    return cfg
}

ActionIndex(id)
{
    global ActionIds
    for index, value in ActionIds
        if value = id
            return index
    return 0
}

ValidExe(value)
{
    return Type(value) = "String" && RegExMatch(value, 'i)^[^\\/:*?"<>|\r\n]+\.exe$')
}

NormalizeConfig(raw)
{
    if !(raw is Map)
        throw ValueError("配置根节点必须是 JSON 对象")
    if raw.Has("SchemaVersion") && raw["SchemaVersion"] != 2
        throw ValueError("不支持的配置版本")
    cfg := Defaults()
    for key, bounds in Map("Threshold", [10, 1000], "ShortClickMs", [100, 1500], "LockMs", [0, 250], "AxisRatio", [105, 300], "DebounceMs", [0, 1000], "Debug", [0, 1], "SilentMode", [0, 1])
        if raw.Has(key) && IsInteger(raw[key]) && raw[key] >= bounds[1] && raw[key] <= bounds[2]
            cfg[key] := Integer(raw[key])
    for button in ["XButton1", "XButton2"]
    {
        if !raw.Has(button) || !(raw[button] is Map)
            continue
        for key in ["Enabled", "ShortClick"]
            if raw[button].Has(key) && IsInteger(raw[button][key]) && (raw[button][key] = 0 || raw[button][key] = 1)
                cfg[button][key] := Integer(raw[button][key])
        for direction in ["Left", "Right", "Up", "Down"]
            if raw[button].Has(direction) && Type(raw[button][direction]) = "String" && ActionIndex(raw[button][direction])
                cfg[button][direction] := raw[button][direction]
    }
    if raw.Has("ExcludedApps") && raw["ExcludedApps"] is Array
    {
        seen := Map()
        for exe in raw["ExcludedApps"]
        {
            if Type(exe) != "String"
                continue
            exe := StrLower(Trim(exe))
            if ValidExe(exe) && !seen.Has(exe) && cfg["ExcludedApps"].Length < 100
            {
                cfg["ExcludedApps"].Push(exe)
                seen[exe] := true
            }
        }
    }
    return cfg
}

LoadConfig(path, legacy := "")
{
    if FileExist(path)
    {
        if FileGetSize(path) > 1024 * 1024
            throw ValueError("配置文件超过 1 MB")
        return NormalizeConfig(Json.Parse(FileRead(path, "UTF-8")))
    }
    cfg := Defaults()
    if legacy != "" && FileExist(legacy)
    {
        raw := Map()
        for key in ["Threshold", "ShortClickMs"]
            raw[key] := IniRead(legacy, "Gesture", key, cfg[key])
        for button in ["XButton1", "XButton2"]
        {
            raw[button] := Map()
            for key, fallback in cfg[button]
                raw[button][key] := IniRead(legacy, button, key, fallback)
        }
        cfg := NormalizeConfig(raw)
    }
    return cfg
}

WriteConfig(path, cfg)
{
    temp := path ".tmp"
    try
    {
        if FileExist(temp)
            FileDelete temp
        FileAppend Json.Dump(cfg) "`n", temp, "UTF-8-RAW"
        if FileExist(path)
            FileCopy path, path ".bak", 1
        FileMove temp, path, 1
    }
    finally
    {
        if FileExist(temp)
            FileDelete temp
    }
}

ForegroundApp()
{
    try return StrLower(WinGetProcessName("A"))
    catch
        return ""
}

IsExcluded(exe, cfg := 0)
{
    global Config
    if !cfg
        cfg := Config
    for name in cfg["ExcludedApps"]
        if StrLower(exe) = name
            return true
    return false
}

ShouldHandle(*)
{
    global Paused, Detecting
    return !Paused && !Detecting && !IsExcluded(ForegroundApp())
}

ApplyConfig()
{
    global Config, Generation, AppliedContext
    Generation++
    enabled := ShouldHandle()
    AppliedContext := enabled
    HotIf
    for button in ["XButton1", "XButton2"]
    {
        capture := enabled && Config[button]["Enabled"]
        prefix := capture ? "*" : "~*"
        Hotkey prefix button, capture ? HandleGesture.Bind(button) : DetectionEvent.Bind(button, "按下／滚动"), "On I1"
        Hotkey prefix button " up", capture ? ((*) => 0) : DetectionEvent.Bind(button, "松开"), "On I1"
    }
}

NewTrack()
{
    return Map("Locked", "", "Candidate", "", "Since", 0, "Peak", 0)
}

UpdateDirection(state, dx, dy, now, cfg)
{
    state["Peak"] := Max(state["Peak"], Abs(dx), Abs(dy))
    if state["Locked"] != ""
        return
    candidate := ""
    ratio := cfg["AxisRatio"] / 100
    if Abs(dx) > cfg["Threshold"] && Abs(dx) >= Abs(dy) * ratio
        candidate := dx > 0 ? "Right" : "Left"
    else if Abs(dy) > cfg["Threshold"] && Abs(dy) >= Abs(dx) * ratio
        candidate := dy > 0 ? "Down" : "Up"
    if candidate != state["Candidate"]
    {
        state["Candidate"] := candidate
        state["Since"] := now
    }
    if candidate != "" && now - state["Since"] >= cfg["LockMs"]
        state["Locked"] := candidate
}

LockedAction(state, dx, dy, cfg, settings)
{
    direction := state["Locked"]
    if direction = ""
        return "none"
    distance := direction = "Right" ? dx : direction = "Left" ? -dx : direction = "Up" ? -dy : dy
    return distance > cfg["Threshold"] * 0.65 ? settings[direction] : "none"
}

ShouldReplay(peak, duration, cfg, settings)
{
    return settings["ShortClick"] && peak <= cfg["Threshold"] && duration <= cfg["ShortClickMs"]
}

HandleGesture(button, *)
{
    global Config, Busy, Paused, Generation, LastActionAt, Detecting
    if Busy
        return
    ; A foreground switch can precede the context timer. Preserve native button
    ; semantics immediately in that small window, without running any gesture.
    if !ShouldHandle()
    {
        Busy := true
        try
        {
            SendLevel 0
            SendEvent "{Blind}{" button " down}"
            KeyWait button
            SendEvent "{Blind}{" button " up}"
        }
        finally
            Busy := false
        return
    }
    Busy := true
    cfg := Config, settings := cfg[button], version := Generation
    started := A_TickCount, app := ForegroundApp(), window := WinExist("A")
    MouseGetPos &startX, &startY
    state := NewTrack(), cancelled := false
    other := button = "XButton1" ? "XButton2" : "XButton1"
    Log("gesture_start", "button=" button " app=" app)
    try
    {
        while GetKeyState(button, "P")
        {
            MouseGetPos &x, &y
            before := state["Locked"]
            UpdateDirection(state, x - startX, y - startY, A_TickCount, cfg)
            if before = "" && state["Locked"] != ""
                Log("direction_lock", "button=" button " direction=" state["Locked"])
            if Paused || Detecting || version != Generation || GetKeyState(other, "P") || WinExist("A") != window
                cancelled := true
            Sleep 10
        }
        MouseGetPos &endX, &endY
        dx := endX - startX, dy := endY - startY
        UpdateDirection(state, dx, dy, A_TickCount, cfg)
        if cancelled || Paused || Detecting || version != Generation || WinExist("A") != window || IsExcluded(ForegroundApp())
        {
            Log("gesture_cancel", "button=" button " reason=context_or_settings_changed")
            return
        }
        duration := A_TickCount - started
        action := LockedAction(state, dx, dy, cfg, settings)
        if action != "none"
        {
            if A_TickCount - LastActionAt < cfg["DebounceMs"]
                Log("gesture_debounce", "button=" button)
            else
            {
                LastActionAt := A_TickCount
                Log("action", "button=" button " action=" action " app=" app)
                ExecuteAction(action)
            }
        }
        else if ShouldReplay(state["Peak"], duration, cfg, settings)
        {
            Log("short_click", "button=" button " app=" app)
            SendLevel 0
            SendEvent "{Blind}{" button "}"
        }
        Log("gesture_end", "button=" button " dx=" dx " dy=" dy " ms=" duration " locked=" state["Locked"] " action=" action)
    }
    catch as err
        Log("gesture_error", err.Message)
    finally
        Busy := false
}

ExecuteAction(action)
{
    switch action
    {
        case "desktop_left": Send "#^{Left}"
        case "desktop_right": Send "#^{Right}"
        case "task_view": Send "#{Tab}"
        case "show_desktop": Send "#d"
        case "next_window": Send "!{Tab}"
        case "maximize":
            if WinGetMinMax("A") = 1
                WinRestore "A"
            else
                WinMaximize "A"
    }
}

UpdateContext(*)
{
    global LastExternalApp, ContextText, SettingsGui, SelfExe, Busy, AppliedContext
    app := ForegroundApp()
    if app != "" && app != SelfExe
        LastExternalApp := app
    text := IsExcluded(app) ? "白名单应用：" app " · 手势已自动禁用" : "当前应用：" app " · 使用全局手势"
    if text != ContextText
    {
        ContextText := text
        RefreshTray()
        Log("context", "app=" app " excluded=" IsExcluded(app))
    }
    if !Busy && AppliedContext != ShouldHandle()
        ApplyConfig()
}

RefreshTray()
{
    global Paused, Detecting, Config
    status := Detecting ? "检测模式" : Paused ? "已暂停" : IsExcluded(ForegroundApp()) ? "应用白名单 · 已禁用" : "已启用"
    A_IconTip := "鼠标桌面手势 1.5.1 · " status
    for item, checked in Map("暂停手势", Paused, "开机启动", StartupEnabled(), "静默模式", Config["SilentMode"], "Debug 日志", Config["Debug"], "鼠标按键检测", Detecting)
        if checked
            A_TrayMenu.Check(item)
        else
            A_TrayMenu.Uncheck(item)
    A_IconHidden := !!Config["SilentMode"]
    UpdateUiStatus()
}

ToggleSilentMode(*)
{
    global Config, ConfigPath, SettingsGui
    cfg := Json.Parse(Json.Dump(Config))
    cfg["SilentMode"] := !cfg["SilentMode"]
    try WriteConfig(ConfigPath, cfg)
    catch as err
    {
        MsgBox err.Message, "无法保存静默模式", "Icon!"
        return
    }
    Config := cfg
    RefreshTray()
    if SettingsGui
    {
        SettingsGui["SilentMode"].Value := cfg["SilentMode"]
        UiRefreshSwitches(SettingsGui)
    }
}

TogglePause(*)
{
    global Paused
    Paused := !Paused
    ApplyConfig()
    RefreshTray()
    Log("pause", "enabled=" Paused)
}

Log(event, details := "")
{
    global Config, BaseDir, LogFailed
    if !Config["Debug"] || LogFailed
        return
    try
    {
        folder := BaseDir "\logs"
        DirCreate folder
        path := folder "\debug.log"
        if FileExist(path) && FileGetSize(path) > 1024 * 1024
            FileMove path, path ".1", 1
        details := StrReplace(StrReplace(details, "`r", " "), "`n", " ")
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " tick=" A_TickCount " " event " " details "`n", path, "UTF-8-RAW"
    }
    catch
    {
        LogFailed := true
        TrayTip "日志目录无法写入，当前运行期间已停止写日志。", "鼠标桌面手势", "Icon!"
    }
}

ToggleDebug(*)
{
    global Config, ConfigPath, SettingsGui, LogFailed
    cfg := Json.Parse(Json.Dump(Config))
    cfg["Debug"] := !Config["Debug"]
    try WriteConfig(ConfigPath, cfg)
    catch as err
    {
        MsgBox err.Message, "无法保存 Debug 设置", "Icon!"
        return
    }
    Log("debug", "disabled=1")
    Config := cfg, LogFailed := false
    RefreshTray()
    if SettingsGui
        SettingsGui["Debug"].Value := Config["Debug"]
    if SettingsGui
        UiRefreshSwitches(SettingsGui)
    Log("debug", "enabled=1")
}

OpenLogs(*)
{
    global BaseDir
    try
    {
        DirCreate BaseDir "\logs"
        Run 'explorer.exe "' BaseDir '\logs"'
    }
    catch as err
        MsgBox err.Message, "无法打开日志目录", "Icon!"
}

RegisterDetection()
{
    global DetectionKeys
    HotIf
    for key in DetectionKeys
    {
        if InStr(key, "XButton")
            continue
        Hotkey "~*" key, DetectionEvent.Bind(key, "按下／滚动"), "Off I1"
        if !InStr(key, "Wheel")
            Hotkey "~*" key " up", DetectionEvent.Bind(key, "松开"), "Off I1"
    }
}

SetDetection(enabled)
{
    global Detecting, Generation, DetectionKeys
    Detecting := enabled
    Generation++
    HotIf
    for key in DetectionKeys
    {
        if InStr(key, "XButton")
            continue
        Hotkey "~*" key, enabled ? "On" : "Off"
        if !InStr(key, "Wheel")
            Hotkey "~*" key " up", enabled ? "On" : "Off"
    }
    ApplyConfig()
    RefreshTray()
    Log("detection_mode", "enabled=" enabled)
}

ShowDetector(*)
{
    global DetectorGui, IconResource
    if DetectorGui
    {
        DetectorGui.Show()
        return
    }
    g := UiBase("鼠标桌面手势 · 按键检测")
    if FileExist(IconResource)
        g.AddPicture("x24 y24 w36 h36 Icon1", IconResource)
    g.SetFont("s16 bold c0F172A")
    g.AddText("x76 y22 w540 h30 BackgroundF5F7FB", "鼠标按键检测")
    g.SetFont("s9 norm c64748B")
    g.AddText("x76 y58 w600 h20 BackgroundF5F7FB", "按下鼠标按键，查看系统识别到的名称与事件。")
    g.SetFont("s10 c334155")
    g.AddText("x24 y97 w660 h30 0x200 BackgroundEAF2FF c2563EB", "  手势暂时停用，鼠标功能正常传递。60 秒后自动结束。")
    g.AddListView("x24 y148 w660 h248 vEvents BackgroundFFFFFF", ["时间", "按键名称", "事件"])
    g["Events"].ModifyCol(1, 140), g["Events"].ModifyCol(2, 200), g["Events"].ModifyCol(3, 260)
    g.SetFont("s9 c94A3B8")
    g.AddText("x24 y411 w380 h20 BackgroundF5F7FB vDetectionCount", "最近记录 0 / 100")
    g.SetFont("s10 c334155")
    UiButton(g, "x24 y449 w120 h38", "清空记录", ClearDetection, "secondary", "F5F7FB")
    UiButton(g, "x548 y449 w136 h38", "结束检测", StopDetection, "primary", "F5F7FB")
    g.OnEvent("Close", StopDetection), g.OnEvent("Escape", StopDetection)
    DetectorGui := g
    SetDetection(true)
    SetTimer StopDetection, -60000
    g.Show("w708 h510")
}

ClearDetection(*)
{
    global DetectorGui
    DetectorGui["Events"].Delete()
    DetectorGui["DetectionCount"].Text := "最近记录 0 / 100"
}

DetectionEvent(key, event, *)
{
    global DetectorGui, Detecting
    if !Detecting || !DetectorGui
        return
    list := DetectorGui["Events"]
    if list.GetCount() >= 100
        list.Delete(1)
    row := list.Add("", FormatTime(, "HH:mm:ss"), key, event)
    list.Modify(row, "Vis")
    DetectorGui["DetectionCount"].Text := "最近记录 " list.GetCount() " / 100"
    Log("mouse_detect", "button=" key " event=" event)
}

StopDetection(*)
{
    global DetectorGui
    SetTimer StopDetection, 0
    SetDetection(false)
    if DetectorGui
        DestroyUi(DetectorGui)
    DetectorGui := 0
}

StartupEnabled()
{
    global StartupPath
    return !!FileExist(StartupPath)
}

SetStartup(enabled)
{
    global StartupPath
    if enabled
    {
        target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
        args := A_IsCompiled ? "--startup" : '"' A_ScriptFullPath '" --startup'
        FileCreateShortcut target, StartupPath, A_ScriptDir, args, "鼠标桌面手势"
    }
    else if FileExist(StartupPath)
        FileDelete StartupPath
}

ToggleStartup(*)
{
    global SettingsGui
    try SetStartup(!StartupEnabled())
    catch as err
    {
        MsgBox err.Message, "无法更改开机启动", "Icon!"
        return
    }
    RefreshTray()
    if SettingsGui
        SettingsGui["Startup"].Value := StartupEnabled()
    if SettingsGui
        UiRefreshSwitches(SettingsGui)
}

AddButtonControls(g)
{
    global ActionLabels
    for index, button in ["XButton1", "XButton2"]
    {
        x := index = 1 ? 236 : 536
        UiText(g, "x" x " y208 w264 h24", index = 1 ? "后退侧键" : "前进侧键", 12, "0F172A", true)
        UiText(g, "x" x " y237 w264 h20", button, 9, "94A3B8")
        UiSwitch(g, "x" x " y267 w264 h32 v" button "Enabled", "启用手势")
        UiSwitch(g, "x" x " y307 w264 h32 v" button "ShortClick", "短按保留原功能")
        for row, direction in ["Left", "Right", "Up", "Down"]
        {
            y := 353 + (row - 1) * 40
            UiText(g, "x" x " y" (y + 4) " w46 h24", ["向左", "向右", "向上", "向下"][row], 10, "64748B")
            g.AddDropDownList("x" (x + 56) " y" y " w208 v" button direction, ActionLabels)
        }
    }
    g.AddText("x518 y207 w1 h306 BackgroundE8EDF4", "")
}

ControlSnapshot(g)
{
    result := Map()
    for control in g
        result[control.Hwnd] := true
    return result
}

RememberPage(g, page, before)
{
    global PageControls
    PageControls[page] := []
    for control in g
        if !before.Has(control.Hwnd)
            PageControls[page].Push(control)
}

PageHeading(g, title, subtitle)
{
    UiText(g, "x236 y132 w580 h30", title, 15, "0F172A", true)
    UiText(g, "x236 y169 w580 h24", subtitle, 9, "64748B")
}

SwitchSettingsPage(page, *)
{
    global PageControls, NavigationButtons, ThemeButtons, SettingsGui
    for index, controls in PageControls
        for control in controls
            control.Visible := index = page && control.Type != "CheckBox"
    for index, button in NavigationButtons
    {
        ThemeButtons[button.Hwnd]["Style"] := index = page ? "nav-selected" : "nav"
        DllCall("user32\InvalidateRect", "Ptr", button.Hwnd, "Ptr", 0, "Int", true)
    }
}

UpdateUiStatus()
{
    global SettingsGui, Paused, Detecting, SelfExe
    if !SettingsGui
        return
    app := ForegroundApp()
    excluded := IsExcluded(app)
    status := Detecting ? "按键检测中" : Paused ? "手势已暂停" : excluded ? "当前应用已禁用" : "手势已启用"
    color := Detecting || Paused || excluded ? "B45309" : "15803D"
    background := Detecting || Paused || excluded ? "FFF6E5" : "EAF7EF"
    SettingsGui["UiStatus"].Opt("c" color " Background" background)
    SettingsGui["UiStatus"].Text := status
    name := app = SelfExe ? "设置窗口" : app = "" ? "桌面" : app
    SettingsGui["UiContext"].Text := "前台：" name
    SettingsGui["PauseAction"].Text := Paused ? "恢复手势" : "暂停手势"
}

BuildSettings()
{
    global SettingsGui, Config, DraftApps, IconResource, PageControls, NavigationButtons
    g := UiBase("鼠标桌面手势 1.5.1 · 设置")
    SettingsGui := g
    PageControls := Map(), NavigationButtons := Map()
    if FileExist(IconResource)
        g.AddPicture("x24 y24 w44 h44 Icon1", IconResource)
    g.SetFont("s18 bold c0F172A")
    g.AddText("x84 y21 w450 h32 BackgroundF5F7FB", "鼠标桌面手势")
    g.SetFont("s9 norm c64748B")
    g.AddText("x86 y61 w440 h20 BackgroundF5F7FB", "让每一次侧键滑动，都更顺手。")
    g.SetFont("s10 c15803D")
    g.AddText("x630 y26 w200 h30 Center 0x200 BackgroundEAF7EF vUiStatus", "手势已启用")
    g.SetFont("s9 c64748B")
    g.AddText("x520 y64 w310 h20 Right BackgroundF5F7FB vUiContext", "")
    g.SetFont("s10 c334155")
    g.AddText("x24 y94 w812 h1 BackgroundE2E8F0", "")
    UiCard(g, 20, 112, 172, 436)
    UiText(g, "x40 y133 w130 h20", "设置", 9, "94A3B8")
    for index, label in ["常规设置", "侧键手势", "应用白名单", "配置管理"]
        NavigationButtons[index] := UiButton(g, "x32 y" (171 + (index - 1) * 54) " w148 h42", label, SwitchSettingsPage.Bind(index), "nav")
    UiText(g, "x40 y462 w130 h18", "VERSION 1.5.1", 8, "94A3B8")
    UiButton(g, "x32 y492 w148 h34", "关于这个应用", ShowAbout, "nav")
    UiCard(g, 212, 112, 628, 436)

    before := ControlSnapshot(g)
    PageHeading(g, "常规设置", "调整手势的响应方式，找到适合自己的节奏。")
    labels := ["移动阈值", "短按时限", "方向稳定时间", "方向优势比例", "连续手势间隔"]
    hints := ["10–1000 像素", "100–1500 毫秒", "0–250 毫秒", "105–300 %", "0–1000 毫秒"]
    keys := ["Threshold", "ShortClickMs", "LockMs", "AxisRatio", "DebounceMs"]
    for index, key in keys
    {
        y := 212 + (index - 1) * 39
        UiText(g, "x236 y" (y + 4) " w264 h23", labels[index], 10)
        g.AddEdit("x528 y" y " w84 v" key " Number", Config[key])
        UiText(g, "x636 y" (y + 5) " w176 h22", hints[index], 9, "94A3B8")
    }
    g.AddText("x236 y410 w580 h1 BackgroundEEF2F7", "")
    UiSwitch(g, "x236 y422 w264 h32 vDebug", "Debug 日志")
    UiSwitch(g, "x536 y422 w264 h32 vStartup", "开机启动")
    UiSwitch(g, "x236 y464 w264 h32 vSilentMode", "静默模式")
    UiText(g, "x536 y470 w272 h22", "隐藏托盘；再次打开 EXE 可管理", 9, "64748B")
    UiButton(g, "x236 y506 w132 h32", "检测按键", ShowDetector)
    UiButton(g, "x380 y506 w132 h32", "查看日志", OpenLogs)
    UiButton(g, "x524 y506 w132 h32 vPauseAction", "暂停手势", TogglePause)
    UiButton(g, "x668 y506 w148 h32", "退出程序", (*) => ExitApp())
    RememberPage(g, 1, before)

    before := ControlSnapshot(g)
    PageHeading(g, "侧键手势", "分别配置两个侧键。短按继续执行鼠标的原有功能。")
    AddButtonControls(g)
    RememberPage(g, 2, before)

    before := ControlSnapshot(g)
    PageHeading(g, "应用白名单", "这些应用在前台时自动停用手势，切走后自动恢复。")
    g.AddListView("x236 y212 w580 h190 vApps BackgroundFFFFFF", ["禁用手势的应用进程"])
    g["Apps"].ModifyCol(1, 550)
    UiText(g, "x236 y418 w580 h20", "添加进程名，例如 game.exe", 9, "64748B")
    g.AddEdit("x236 y446 w276 h28 vNewExe", "")
    UiButton(g, "x524 y444 w104 h32", "添加", AddApp)
    UiButton(g, "x640 y444 w176 h32", "选择应用…", BrowseApp)
    UiButton(g, "x236 y496 w178 h32", "添加上一个应用", AddLastApp)
    UiButton(g, "x432 y496 w142 h32", "移除选中项", RemoveApp)
    RememberPage(g, 3, before)

    before := ControlSnapshot(g)
    PageHeading(g, "配置管理", "分享你的使用习惯，或回到上一份熟悉的设置。")
    UiText(g, "x236 y218 w168 h28", "导入配置", 11, "0F172A", true)
    UiText(g, "x236 y254 w168 h46", "选择 JSON 文件，`n载入后可以先预览。", 9, "64748B")
    UiButton(g, "x236 y316 w168 h38", "导入配置…", ImportConfig)
    UiText(g, "x436 y218 w168 h28", "导出配置", 11, "0F172A", true)
    UiText(g, "x436 y254 w168 h46", "分享当前界面设置，`n不会改变本机配置。", 9, "64748B")
    UiButton(g, "x436 y316 w168 h38", "导出配置…", ExportConfig)
    UiText(g, "x636 y218 w180 h28", "恢复上一份", 11, "0F172A", true)
    UiText(g, "x636 y254 w180 h46", "载入自动备份，`n保存后再生效。", 9, "64748B")
    UiButton(g, "x636 y316 w180 h38 vRestorePrevious", "恢复上一份设置", RestorePrevious)
    UiText(g, "x236 y393 w580 h62 vTransferStatus", "导入和恢复后，请检查设置，再点击“保存并应用”。", 10, "2563EB")
    g.AddText("x236 y470 w580 h1 BackgroundEEF2F7", "")
    UiText(g, "x236 y489 w580 h36", "开机启动使用本机选项，不随配置分享。导入文件不会执行命令。", 9, "94A3B8")
    RememberPage(g, 4, before)

    UiText(g, "x24 y569 w340 h24 BackgroundF5F7FB", "修改仅在保存后生效", 9, "94A3B8")
    UiButton(g, "x404 y562 w130 h38", "恢复默认值", RestoreDefaults, "secondary", "F5F7FB")
    UiButton(g, "x550 y562 w110 h38", "取消", CloseSettings, "secondary", "F5F7FB")
    UiButton(g, "x676 y562 w164 h38 Default", "保存并应用", SaveSettings, "primary", "F5F7FB")
    g.OnEvent("Close", CloseSettings), g.OnEvent("Escape", CloseSettings)
    FillSettings(Config)
    SwitchSettingsPage(1)
    UpdateUiStatus()
    return g
}

FillSettings(cfg)
{
    global SettingsGui, DraftApps, ConfigPath
    for key in ["Threshold", "ShortClickMs", "LockMs", "AxisRatio", "DebounceMs", "Debug", "SilentMode"]
        SettingsGui[key].Value := cfg[key]
    SettingsGui["Startup"].Value := StartupEnabled()
    for button in ["XButton1", "XButton2"]
    {
        for key in ["Enabled", "ShortClick"]
            SettingsGui[button key].Value := cfg[button][key]
        for direction in ["Left", "Right", "Up", "Down"]
            SettingsGui[button direction].Choose(ActionIndex(cfg[button][direction]))
    }
    DraftApps := cfg["ExcludedApps"].Clone()
    RefreshApps()
    SettingsGui["RestorePrevious"].Enabled := !!FileExist(ConfigPath ".bak")
    UiRefreshSwitches(SettingsGui)
}

RestoreDefaults(*)
{
    FillSettings(Defaults())
}

ReadTransferConfig(path)
{
    if !FileExist(path) || FileGetSize(path) > 1024 * 1024
        throw ValueError("配置文件不存在或超过 1 MB。")
    raw := Json.Parse(FileRead(path, "UTF-8"))
    if !(raw is Map) || !raw.Has("SchemaVersion") || raw["SchemaVersion"] != 2
        throw ValueError("不是支持的配置文件（需要 JSON 配置版本 2）。")
    for key, limits in Map("Threshold", [10, 1000], "ShortClickMs", [100, 1500], "LockMs", [0, 250], "AxisRatio", [105, 300], "DebounceMs", [0, 1000], "Debug", [0, 1], "SilentMode", [0, 1])
        if raw.Has(key) && (!IsInteger(raw[key]) || raw[key] < limits[1] || raw[key] > limits[2])
            throw ValueError("配置参数无效：" key)
    for button in ["XButton1", "XButton2"]
    {
        if !raw.Has(button)
            continue
        if !(raw[button] is Map)
            throw ValueError("侧键配置必须是对象：" button)
        for key in ["Enabled", "ShortClick"]
            if raw[button].Has(key) && (!IsInteger(raw[button][key]) || (raw[button][key] != 0 && raw[button][key] != 1))
                throw ValueError("侧键选项无效：" button " " key)
        for direction in ["Left", "Right", "Up", "Down"]
            if raw[button].Has(direction) && (Type(raw[button][direction]) != "String" || !ActionIndex(raw[button][direction]))
                throw ValueError("手势动作无效：" button " " direction)
    }
    if raw.Has("ExcludedApps")
    {
        if !(raw["ExcludedApps"] is Array) || raw["ExcludedApps"].Length > 100
            throw ValueError("应用白名单必须是最多 100 项的数组。")
        for exe in raw["ExcludedApps"]
            if !ValidExe(exe)
                throw ValueError("应用白名单含无效进程名。")
    }
    return NormalizeConfig(raw)
}

LoadTransferPreview(path, label)
{
    global SettingsGui
    cfg := ReadTransferConfig(path)
    localStartup := SettingsGui["Startup"].Value
    FillSettings(cfg)
    SettingsGui["Startup"].Value := localStartup
    UiRefreshSwitches(SettingsGui)
    SettingsGui["TransferStatus"].Text := label "已载入界面。`n请检查各项设置，再点击“保存并应用”。点击“取消”可放弃。"
    return cfg
}

ImportConfig(*)
{
    path := FileSelect(1,, "选择要导入的配置", "JSON 配置 (*.json)")
    if path = ""
        return
    try LoadTransferPreview(path, "导入配置")
    catch as err
        MsgBox "导入失败，现有设置未改变：`n" err.Message, "配置导入", "Icon!"
}

ExportConfigFile(path, cfg)
{
    global ConfigPath
    if StrLower(path) = StrLower(ConfigPath) || StrLower(path) = StrLower(ConfigPath ".bak")
        throw ValueError("请导出到另外一个文件，以免覆盖正在使用的配置或备份。")
    temp := path ".export-tmp"
    try
    {
        if FileExist(temp)
            FileDelete temp
        FileAppend Json.Dump(cfg) "`n", temp, "UTF-8-RAW"
        FileMove temp, path, 1
    }
    finally
    {
        if FileExist(temp)
            FileDelete temp
    }
}

ExportConfig(*)
{
    global SettingsGui
    try
    {
        cfg := SettingsConfig()
        path := FileSelect("S16", "MouseDesktopGestures-settings.json", "导出当前界面的配置", "JSON 配置 (*.json)")
        if path = ""
            return
        if !RegExMatch(path, "i)\.json$")
            path .= ".json"
        ExportConfigFile(path, cfg)
        SplitPath path, &name
        SettingsGui["TransferStatus"].Text := "已导出：" name "`n导出未改变本机正在使用的设置。"
    }
    catch as err
        MsgBox "导出失败：`n" err.Message, "配置导出", "Icon!"
}

RestorePrevious(*)
{
    global ConfigPath
    try LoadTransferPreview(ConfigPath ".bak", "上一份设置")
    catch as err
        MsgBox "无法恢复，现有设置未改变：`n" err.Message, "恢复上一份设置", "Icon!"
}

ShowAbout(*)
{
    global AboutGui, IconResource, AuthorUrl, RepositoryUrl
    if AboutGui
    {
        AboutGui.Show()
        return
    }
    g := UiBase("关于 · 鼠标桌面手势")
    g.BackColor := "FFFFFF"
    if FileExist(IconResource)
        g.AddPicture("x28 y28 w76 h76 Icon1", IconResource)
    UiText(g, "x128 y29 w354 h34", "鼠标桌面手势", 18, "0F172A", true)
    UiText(g, "x130 y76 w354 h22", "Mouse Desktop Gestures", 10, "64748B")
    UiText(g, "x28 y133 w450 h28 vVersionInfo", "版本 1.5.1  ·  Windows 10 / 11 x64", 10, "2563EB")
    g.AddText("x28 y179 w450 h1 BackgroundE8EDF4", "")
    UiText(g, "x28 y203 w450 h74", "按住侧键，滑动切换桌面。`n保留短按原功能，让鼠标操作更顺手。", 11, "334155")
    UiText(g, "x28 y289 w450 h48", "免安装运行  ·  JSON 配置  ·  配置分享`n运行引擎：AutoHotkey " A_AhkVersion, 9, "64748B")
    UiText(g, "x28 y352 w60 h24", "作者：", 10, "334155")
    author := g.AddLink("x87 y352 w360 h24 vAuthorLink", '<a href="' AuthorUrl '">Saksk-IT</a>')
    author.OnEvent("Click", OpenWebLink.Bind(AuthorUrl))
    UiText(g, "x28 y382 w100 h24", "GitHub 仓库：", 10, "334155")
    repository := g.AddLink("x132 y382 w350 h24 vRepositoryLink", '<a href="' RepositoryUrl '">Saksk-IT/MouseDesktopGestures</a>')
    repository.OnEvent("Click", OpenWebLink.Bind(RepositoryUrl))
    UiText(g, "x28 y421 w450 h42", "图标由 AI 生图生成。`n源码与运行引擎许可证随分享包附带。", 9, "94A3B8")
    UiButton(g, "x340 y482 w138 h38 Default", "关闭", CloseAbout, "primary")
    g.OnEvent("Close", CloseAbout), g.OnEvent("Escape", CloseAbout)
    AboutGui := g
    g.Show("w506 h548")
}

OpenWebLink(url, *)
{
    Run url
}

CloseAbout(*)
{
    global AboutGui
    if AboutGui
        DestroyUi(AboutGui)
    AboutGui := 0
}

RefreshApps()
{
    global SettingsGui, DraftApps
    SettingsGui["Apps"].Delete()
    for exe in DraftApps
        SettingsGui["Apps"].Add("", exe)
}

AddApp(*)
{
    global SettingsGui, DraftApps
    exe := StrLower(Trim(SettingsGui["NewExe"].Value))
    if !ValidExe(exe)
    {
        MsgBox "请输入应用进程名，例如 game.exe；不要填写完整路径。", "应用白名单", "Icon!"
        return
    }
    for name in DraftApps
        if name = exe
            return
    if DraftApps.Length >= 100
    {
        MsgBox "最多添加 100 个应用。", "应用白名单", "Icon!"
        return
    }
    DraftApps.Push(exe)
    SettingsGui["NewExe"].Value := ""
    RefreshApps()
}

BrowseApp(*)
{
    global SettingsGui
    path := FileSelect(1,, "选择要禁用手势的应用", "应用程序 (*.exe)")
    if path = ""
        return
    SplitPath path, &name
    SettingsGui["NewExe"].Value := name
    AddApp()
}

AddLastApp(*)
{
    global SettingsGui, LastExternalApp, SelfExe
    if LastExternalApp = ""
    {
        MsgBox "请先切到目标应用，再回到设置窗口。", "应用白名单"
        return
    }
    SettingsGui["NewExe"].Value := LastExternalApp
    AddApp()
}

RemoveApp(*)
{
    global SettingsGui, DraftApps
    indexes := []
    row := 0
    while row := SettingsGui["Apps"].GetNext(row)
        indexes.InsertAt(1, row)
    for index in indexes
        DraftApps.RemoveAt(index)
    RefreshApps()
}

ShowSettings(*)
{
    global SettingsGui, LastExternalApp
    app := ForegroundApp()
    if app != "" && app != SelfExe
        LastExternalApp := app
    if !SettingsGui
        BuildSettings()
    SettingsGui.Show("w860 h620")
}

CloseSettings(*)
{
    global SettingsGui
    if SettingsGui
        DestroyUi(SettingsGui)
    SettingsGui := 0
}

SettingsConfig()
{
    global SettingsGui, ActionIds, DraftApps
    cfg := Defaults()
    for key, limits in Map("Threshold", [10, 1000], "ShortClickMs", [100, 1500], "LockMs", [0, 250], "AxisRatio", [105, 300], "DebounceMs", [0, 1000])
    {
        value := SettingsGui[key].Value
        if !IsInteger(value) || value < limits[1] || value > limits[2]
            throw ValueError(key " 需在 " limits[1] " 至 " limits[2] " 之间。")
        cfg[key] := Integer(value)
    }
    cfg["Debug"] := SettingsGui["Debug"].Value
    cfg["SilentMode"] := SettingsGui["SilentMode"].Value
    cfg["ExcludedApps"] := DraftApps.Clone()
    for button in ["XButton1", "XButton2"]
    {
        for key in ["Enabled", "ShortClick"]
            cfg[button][key] := SettingsGui[button key].Value
        for direction in ["Left", "Right", "Up", "Down"]
            cfg[button][direction] := ActionIds[SettingsGui[button direction].Value]
    }
    return cfg
}

SaveSettings(*)
{
    global Config, ConfigPath, SettingsGui, LogFailed
    try
    {
        cfg := SettingsConfig()
        oldStartup := StartupEnabled()
        SetStartup(SettingsGui["Startup"].Value)
        try WriteConfig(ConfigPath, cfg)
        catch as err
        {
            SetStartup(oldStartup)
            throw err
        }
        Config := cfg, LogFailed := false
        ApplyConfig()
        RefreshTray()
        Log("settings_saved", "excluded_count=" Config["ExcludedApps"].Length)
        CloseSettings()
    }
    catch as err
        MsgBox "设置未保存：`n" err.Message, "鼠标桌面手势", "Icon!"
}

ShowHelp(*)
{
    MsgBox "按住侧键移动，松开执行手势；短按保留后退／前进功能。"
        . "`n方向达到阈值并稳定后锁定；回到起点附近松开可取消。"
        . "`n`n双击托盘图标打开设置。应用白名单中的程序在前台时自动禁用手势。"
        . "`n按键检测期间事件原样传递，60 秒后自动结束。"
        . "`nDebug 日志默认关闭，保存在 logs\debug.log，超过约 1 MB 后轮换。"
        . "`n`n配置为 config.json；首次升级自动读取旧 config.ini，原 INI 保留。"
        . "`n手工修改 JSON 后需重启。保存时上一份 JSON 备份为 config.json.bak。"
        . "`n开机启动是当前用户的启动快捷方式，移动程序后请关闭再开启该选项。",
        "鼠标桌面手势 1.5.1 · 使用说明", "Iconi"
}

Assert(value, message)
{
    if !value
        throw Error(message)
}

TestUiSwitches()
{
    global ThemeButtons, Config
    before := Json.Dump(Config)
    count := 0
    for hwnd, item in ThemeButtons
    {
        if !item.Has("Toggle")
            continue
        value := item["Toggle"]
        SwitchSettingsPage(InStr(value.Name, "XButton") ? 2 : 1)
        Assert(!value.Visible, "Internal checkbox became visible")
        original := value.Value
        PostMessage 0xF5, 0, 0, hwnd
        Sleep 30
        Assert(value.Value = !original, "Switch click did not change its setting")
        PostMessage 0xF5, 0, 0, hwnd
        Sleep 30
        Assert(value.Value = original, "Switch click did not restore its setting")
        count += 1
    }
    Assert(count = 7 && Json.Dump(Config) = before, "Switches changed live config before saving")
    SwitchSettingsPage(1)
}

RunSelfTest()
{
    global Config, ConfigPath, LegacyPath, BaseDir, StartupPath, Paused, SettingsGui, DraftApps, DetectorGui, Detecting, AboutGui
    cfg := Defaults()
    sample := Map("中文", "引号" Chr(34) "和反斜杠\`n换行", "array", [1, -2.5, Json.Null], "emoji", Chr(0x1F600))
    roundtrip := Json.Parse(Json.Dump(sample))
    Assert(roundtrip["中文"] = sample["中文"] && roundtrip["emoji"] = sample["emoji"], "JSON Unicode roundtrip")
    Assert(Json.Parse('"\uD83D\uDE00"') = Chr(0x1F600), "JSON surrogate pair")
    for invalid in ['{"a":1,}', '{"a":1,"a":2}', '[01]', 'true extra', 'True', '"\uD800"']
    {
        rejected := false
        try Json.Parse(invalid)
        catch
            rejected := true
        Assert(rejected, "Invalid JSON accepted: " invalid)
    }
    cfg["XButton1"]["Down"] := "next_window"
    cfg["ExcludedApps"] := ["Game.EXE", "game.exe"]
    WriteConfig(ConfigPath, cfg)
    loaded := LoadConfig(ConfigPath)
    Assert(loaded["XButton1"]["Down"] = "next_window" && loaded["ExcludedApps"].Length = 1, "JSON config roundtrip")
    Assert(IsExcluded("GAME.exe", loaded) && !IsExcluded("browser.exe", loaded), "App exclusion matching")
    if FileExist(LegacyPath)
        FileDelete LegacyPath
    IniWrite 120, LegacyPath, "Gesture", "Threshold"
    IniWrite "next_window", LegacyPath, "XButton1", "Down"
    migrated := LoadConfig(BaseDir "\missing.json", LegacyPath)
    Assert(migrated["Threshold"] = 120 && migrated["XButton1"]["Down"] = "next_window", "INI migration")
    cfg := Defaults(), state := NewTrack()
    UpdateDirection(state, 100, 20, 100, cfg)
    UpdateDirection(state, 100, 20, 120, cfg)
    Assert(state["Locked"] = "", "Premature direction lock")
    UpdateDirection(state, 105, 20, 141, cfg)
    Assert(state["Locked"] = "Right", "Stable direction did not lock")
    UpdateDirection(state, 100, -220, 200, cfg)
    Assert(state["Locked"] = "Right" && LockedAction(state, 100, -220, cfg, cfg["XButton1"]) = "desktop_left", "Locked direction changed")
    Assert(LockedAction(state, 10, 0, cfg, cfg["XButton1"]) = "none", "Return to origin should cancel")
    state := NewTrack()
    UpdateDirection(state, 100, 100, 100, cfg), UpdateDirection(state, 100, 100, 200, cfg)
    Assert(state["Locked"] = "", "Ambiguous diagonal locked")
    Assert(ShouldReplay(5, 200, cfg, cfg["XButton1"]) && !ShouldReplay(100, 200, cfg, cfg["XButton1"]), "Short-click classification")
    Config := cfg
    ApplyConfig()
    BuildSettings()
    TestUiSwitches()
    SettingsGui["SilentMode"].Value := 1
    Assert(SettingsConfig()["SilentMode"] = 1 && Config["SilentMode"] = 0, "Silent mode draft applied early")
    FillSettings(Config)
    Config["SilentMode"] := 1
    RefreshTray()
    Assert(A_IconHidden = 1, "Silent mode did not hide tray icon")
    Config["SilentMode"] := 0
    RefreshTray()
    Assert(A_IconHidden = 0, "Leaving silent mode did not restore tray icon")
    SettingsGui["Threshold"].Value := 100
    SettingsGui["XButton2Up"].Choose(ActionIndex("maximize"))
    SettingsGui["NewExe"].Value := "Game.exe"
    AddApp()
    saved := SettingsConfig()
    Assert(saved["Threshold"] = 100 && saved["XButton2"]["Up"] = "maximize" && saved["ExcludedApps"][1] = "game.exe", "GUI values")
    SaveSettings()
    Assert(LoadConfig(ConfigPath)["Threshold"] = 100, "GUI save")
    TogglePause(), Assert(Paused, "Pause failed")
    TogglePause(), Assert(!Paused, "Resume failed")
    ShowDetector()
    DetectionEvent("XButton2", "松开")
    Assert(Detecting && DetectorGui["Events"].GetCount() = 1 && !ShouldHandle(), "Detector mode")
    StopDetection()
    Assert(!Detecting && !DetectorGui, "Detector cleanup")
    Config["Debug"] := 1
    Log("self_test", "unicode=中文")
    Assert(InStr(FileRead(BaseDir "\logs\debug.log", "UTF-8"), "self_test"), "Debug log not written")
    fill := ""
    Loop 1100
        fill .= "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    Loop 10
        FileAppend fill, BaseDir "\logs\debug.log", "UTF-8-RAW"
    Log("after_rotation")
    Assert(FileExist(BaseDir "\logs\debug.log.1") && FileGetSize(BaseDir "\logs\debug.log") < 1000, "Log rotation failed")
    SetStartup(true)
    FileGetShortcut StartupPath, &target, , &startupArguments
    Assert(target = (A_IsCompiled ? A_ScriptFullPath : A_AhkPath) && InStr(startupArguments, "--startup"), "Startup target or silent launch argument")
    if A_IsCompiled
    {
        FileCreateShortcut A_ScriptFullPath, StartupPath, A_ScriptDir, "", "旧版启动快捷方式"
        MigrateStartupShortcut()
        FileGetShortcut StartupPath, &target, , &startupArguments
        Assert(target = A_ScriptFullPath && startupArguments = "--startup", "Legacy startup shortcut migration")
    }
    SetStartup(false)
    Config := Defaults()
    Config["Threshold"] := 90
    WriteConfig(ConfigPath, Config)
    BuildSettings()
    SettingsGui["Threshold"].Value := 130
    SettingsGui["Startup"].Value := 1
    SettingsGui["SilentMode"].Value := 1
    SettingsGui["NewExe"].Value := "ExportGame.exe"
    AddApp()
    sharePath := BaseDir "\shared-settings.json"
    ExportConfigFile(sharePath, SettingsConfig())
    shared := ReadTransferConfig(sharePath)
    Assert(shared["Threshold"] = 130 && shared["SilentMode"] = 1 && shared["ExcludedApps"][1] = "exportgame.exe", "Export GUI draft failed")
    Assert(!shared.Has("Startup") && !StartupEnabled() && LoadConfig(ConfigPath)["Threshold"] = 90 && Config["Threshold"] = 90, "Export changed live settings or shared startup")
    FillSettings(Defaults())
    SettingsGui["Startup"].Value := 1
    LoadTransferPreview(sharePath, "导入配置")
    Assert(SettingsGui["Threshold"].Value = 130 && SettingsGui["Startup"].Value = 1 && Config["Threshold"] = 90, "Import preview changed live config or local startup")
    CloseSettings()
    Assert(LoadConfig(ConfigPath)["Threshold"] = 90, "Cancel applied imported config")
    BuildSettings()
    LoadTransferPreview(sharePath, "导入配置")
    SaveSettings()
    Assert(Config["Threshold"] = 130 && Config["SilentMode"] = 1 && LoadConfig(ConfigPath ".bak")["Threshold"] = 90, "Import apply or backup failed")
    BuildSettings()
    RestorePrevious()
    Assert(SettingsGui["Threshold"].Value = 90 && Config["Threshold"] = 130, "Restore should only preview")
    SaveSettings()
    Assert(Config["Threshold"] = 90 && LoadConfig(ConfigPath ".bak")["Threshold"] = 130, "Restore apply failed")
    bad := Defaults()
    bad["XButton1"]["Left"] := "run_arbitrary_command"
    badPath := BaseDir "\invalid-transfer.json"
    ExportConfigFile(badPath, bad)
    rejected := false
    try ReadTransferConfig(badPath)
    catch
        rejected := true
    Assert(rejected && Config["Threshold"] = 90, "Invalid transfer was accepted")
    rejected := false
    try ExportConfigFile(ConfigPath, Defaults())
    catch
        rejected := true
    Assert(rejected && LoadConfig(ConfigPath)["Threshold"] = 90, "Export overwrote live config")
    ShowAbout()
    Assert(InStr(AboutGui["VersionInfo"].Text, "1.5.1"), "About version wrong")
    Assert(InStr(AboutGui["AuthorLink"].Text, "Saksk-IT"), "About author missing")
    Assert(InStr(AboutGui["RepositoryLink"].Text, "Saksk-IT/MouseDesktopGestures"), "About repository missing")
    CloseAbout()
}
