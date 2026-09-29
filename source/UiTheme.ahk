; Native Windows UI styling. No web view or additional runtime dependencies.
; SPDX-License-Identifier: GPL-2.0-or-later
ThemeButtons := Map()
ThemeButtonProc := CallbackCreate(ThemeButtonSubclass)
OnMessage(0x2B, DrawThemeButton)

UiBase(title)
{
    g := Gui(, title)
    g.BackColor := "F5F7FB"
    g.SetFont("s10 c334155", "Microsoft YaHei UI")
    return g
}

UiText(g, options, text, size := 10, color := "334155", bold := false)
{
    g.SetFont("s" size " c" color (bold ? " bold" : " norm"))
    control := g.AddText(options (InStr(options, "Background") ? "" : " BackgroundFFFFFF"), text)
    g.SetFont("s10 norm c334155")
    return control
}

UiCard(g, x, y, width, height)
{
    return g.AddText("x" x " y" y " w" width " h" height " BackgroundFFFFFF", "")
}

UiButton(g, options, text, action, style := "secondary", surface := "FFFFFF")
{
    global ThemeButtons
    button := g.AddButton(options " +0xB", text)
    ThemeButtons[button.Hwnd] := Map("Style", style, "Surface", surface)
    DllCall("comctl32\SetWindowSubclass", "Ptr", button.Hwnd, "Ptr", ThemeButtonProc, "UPtr", 1, "UPtr", 0)
    SendMessage(0xF4, 0xB, 1, button.Hwnd)
    button.OnEvent("Click", action)
    return button
}

UiColor(hex)
{
    n := Integer("0x" hex)
    return ((n & 0xFF) << 16) | (n & 0xFF00) | ((n >> 16) & 0xFF)
}

DrawThemeButton(wParam, lParam, *)
{
    global ThemeButtons
    handleOffset := A_PtrSize = 8 ? 24 : 20
    handle := NumGet(lParam, handleOffset, "Ptr")
    if !ThemeButtons.Has(handle)
        return
    item := ThemeButtons[handle]
    dc := NumGet(lParam, handleOffset + A_PtrSize, "Ptr")
    rectOffset := handleOffset + A_PtrSize * 2
    rect := lParam + rectOffset
    state := NumGet(lParam, 16, "UInt")
    disabled := !!(state & 4), pressed := !!(state & 1)
    primary := item["Style"] = "primary"
    nav := item["Style"] = "nav"
    selectedNav := item["Style"] = "nav-selected"
    fill := disabled ? "F1F5F9" : primary ? (pressed ? "1D4ED8" : "2563EB") : (pressed ? "EDF2F7" : "FFFFFF")
    border := primary && !disabled ? fill : "DCE4EE"
    text := disabled ? "94A3B8" : primary ? "FFFFFF" : "334155"
    if nav || selectedNav
    {
        fill := selectedNav ? "EAF2FF" : pressed ? "F1F5F9" : "FFFFFF"
        border := fill
        text := selectedNav ? "1D4ED8" : "475569"
    }
    saved := DllCall("gdi32\SaveDC", "Ptr", dc, "Int")
    surface := DllCall("gdi32\CreateSolidBrush", "UInt", UiColor(item["Surface"]), "Ptr")
    brush := DllCall("gdi32\CreateSolidBrush", "UInt", UiColor(fill), "Ptr")
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", UiColor(border), "Ptr")
    try
    {
        DllCall("user32\FillRect", "Ptr", dc, "Ptr", rect, "Ptr", surface)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", brush)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen)
        left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
        radius := Round(8 * A_ScreenDPI / 96)
        DllCall("gdi32\RoundRect", "Ptr", dc, "Int", left, "Int", top, "Int", right, "Int", bottom, "Int", radius, "Int", radius)
        font := SendMessage(0x31, 0, 0, handle)
        if font
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font)
        DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", UiColor(text))
        if item.Has("Toggle")
            DrawSwitchContent(dc, rect, item, disabled)
        else
        {
            label := GuiCtrlFromHwnd(handle).Text
            DllCall("user32\DrawTextW", "Ptr", dc, "Str", label, "Int", -1, "Ptr", rect, "UInt", 0x25)
        }
        if (state & 16) && !disabled
        {
            focusRect := Buffer(16)
            NumPut("Int", left + 5, "Int", top + 5, "Int", right - 5, "Int", bottom - 5, focusRect)
            DllCall("user32\DrawFocusRect", "Ptr", dc, "Ptr", focusRect)
        }
    }
    finally
    {
        DllCall("gdi32\RestoreDC", "Ptr", dc, "Int", saved)
        for object in [surface, brush, pen]
            DllCall("gdi32\DeleteObject", "Ptr", object)
    }
    return true
}

DestroyUi(g)
{
    global ThemeButtons
    for control in g
        if ThemeButtons.Has(control.Hwnd)
            ThemeButtons.Delete(control.Hwnd)
    g.Destroy()
}


ThemeButtonSubclass(hwnd, message, wParam, lParam, subclassId, reference)
{
    if message = 0xF4
        wParam := (wParam & ~0xF) | 0xB
    return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", message, "UPtr", wParam, "Ptr", lParam, "Ptr")
}


; The hidden native checkbox retains the existing config/GUI Value contract.
; Its visible button provides a large mouse target and normal Tab/Space access.
UiSwitch(g, options, label)
{
    global ThemeButtons
    value := g.AddCheckbox(options " Hidden", "")
    buttonOptions := RegExReplace(options, "\bv\w+", "")
    button := UiButton(g, buttonOptions, label, ToggleUiSwitch, "secondary")
    ThemeButtons[button.Hwnd]["Toggle"] := value
    ThemeButtons[button.Hwnd]["Label"] := label
    return button
}

ToggleUiSwitch(button, *)
{
    global ThemeButtons
    value := ThemeButtons[button.Hwnd]["Toggle"]
    value.Value := !value.Value
    DllCall("user32\InvalidateRect", "Ptr", button.Hwnd, "Ptr", 0, "Int", true)
}

UiRefreshSwitches(g)
{
    global ThemeButtons
    for control in g
        if ThemeButtons.Has(control.Hwnd) && ThemeButtons[control.Hwnd].Has("Toggle")
            DllCall("user32\InvalidateRect", "Ptr", control.Hwnd, "Ptr", 0, "Int", true)
}

DrawSwitchContent(dc, rect, item, disabled)
{
    on := !!item["Toggle"].Value
    scale := A_ScreenDPI / 96
    left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
    right := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
    x := left + Round(10 * scale), y := (top + bottom - Round(20 * scale)) // 2
    width := Round(36 * scale), height := Round(20 * scale)
    brush := DllCall("gdi32\CreateSolidBrush", "UInt", UiColor(disabled ? "CBD5E1" : on ? "2563EB" : "64748B"), "Ptr")
    knob := DllCall("gdi32\CreateSolidBrush", "UInt", UiColor("FFFFFF"), "Ptr")
    saved := DllCall("gdi32\SaveDC", "Ptr", dc, "Int")
    try
    {
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", DllCall("gdi32\GetStockObject", "Int", 8, "Ptr"))
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", brush)
        DllCall("gdi32\RoundRect", "Ptr", dc, "Int", x, "Int", y, "Int", x + width, "Int", y + height, "Int", height, "Int", height)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", knob)
        inset := Round(3 * scale), size := height - inset * 2
        knobX := on ? x + width - inset - size : x + inset
        DllCall("gdi32\Ellipse", "Ptr", dc, "Int", knobX, "Int", y + inset, "Int", knobX + size, "Int", y + inset + size)
        textRect := Buffer(16)
        NumPut("Int", left + Round(56 * scale), "Int", top, "Int", right - Round(57 * scale), "Int", bottom, textRect)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", UiColor(disabled ? "94A3B8" : "334155"))
        DllCall("user32\DrawTextW", "Ptr", dc, "Str", item["Label"], "Int", -1, "Ptr", textRect, "UInt", 0x24)
        NumPut("Int", right - Round(53 * scale), "Int", top, "Int", right - Round(8 * scale), "Int", bottom, textRect)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", UiColor(disabled ? "94A3B8" : on ? "1D4ED8" : "64748B"))
        DllCall("user32\DrawTextW", "Ptr", dc, "Str", on ? "已开启" : "已关闭", "Int", -1, "Ptr", textRect, "UInt", 0x26)
    }
    finally
    {
        DllCall("gdi32\RestoreDC", "Ptr", dc, "Int", saved)
        DllCall("gdi32\DeleteObject", "Ptr", brush)
        DllCall("gdi32\DeleteObject", "Ptr", knob)
    }
}
