param(
    [Parameter(Mandatory)][string]$Executable,
    [int]$Iterations = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scratch = Join-Path $root ("dist/instance-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$isolatedExe = Join-Path $scratch 'MouseDesktopGestures.exe'
Copy-Item -LiteralPath $Executable -Destination $isolatedExe
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw -Encoding UTF8).Trim()
$windowTitle = "鼠标桌面手势 $version · 设置"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GestureWindow {
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
}
'@

function Get-IsolatedProcesses {
    @(Get-Process -Name 'MouseDesktopGestures' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $isolatedExe })
}

for ($attempt = 1; $attempt -le $Iterations; $attempt++) {
    try {
        $first = Start-Process -FilePath $isolatedExe -ArgumentList '--startup' -PassThru -WindowStyle Hidden
        $second = Start-Process -FilePath $isolatedExe -ArgumentList '--settings' -PassThru -WindowStyle Hidden
        if (-not $second.WaitForExit(10000) -and -not $first.HasExited) {
            throw "第 $attempt 次：第二次启动未及时退出。"
        }
        $found = $false
        for ($probe = 0; $probe -lt 30; $probe++) {
            $running = @(Get-IsolatedProcesses)
            $window = if ($running.Count -eq 1) { $running[0].MainWindowHandle } else { [IntPtr]::Zero }
            $windowPid = [uint32]0
            if ($window -ne [IntPtr]::Zero) { [void][GestureWindow]::GetWindowThreadProcessId($window, [ref]$windowPid) }
            if ($running.Count -eq 1 -and $windowPid -eq [uint32]$running[0].Id -and [GestureWindow]::IsWindowVisible($window)) {
                $found = $true
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $found) {
            $running = @(Get-IsolatedProcesses)
            $titles = ($running | ForEach-Object { "$($_.Id):$($_.MainWindowTitle)" }) -join ', '
            $window = if ($running.Count -eq 1) { $running[0].MainWindowHandle } else { [IntPtr]::Zero }
            $windowPid = [uint32]0
            if ($window -ne [IntPtr]::Zero) { [void][GestureWindow]::GetWindowThreadProcessId($window, [ref]$windowPid) }
            throw "第 $attempt 次：设置窗口未打开或常驻进程数量错误。进程数=$($running.Count)；窗口=$titles；句柄=$window；窗口进程=$windowPid；可见=$([GestureWindow]::IsWindowVisible($window))。"
        }
    }
    finally {
        Get-IsolatedProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 50
    }
}
Write-Host "单实例并发启动验证通过：$Iterations 次。"
