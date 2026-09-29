param(
    [switch]$Package,
    [switch]$InstanceStress,
    [switch]$UpdateTrackedExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolsDir = Join-Path $root '.tools'
$distDir = Join-Path $root 'dist'
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw -Encoding UTF8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION 格式无效。' }
if ($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME -ne "v$version") {
    throw "标签 $env:GITHUB_REF_NAME 与 VERSION $version 不一致。"
}

function Assert-Contains([string]$relativePath, [string]$needle) {
    $content = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw -Encoding UTF8
    if (-not $content.Contains($needle)) { throw "$relativePath 缺少版本标记：$needle" }
}

Assert-Contains 'source/MouseDesktopGestures.ahk' ";@Ahk2Exe-SetVersion $version"
Assert-Contains 'source/MouseDesktopGestures.ahk' "version=$version"
Assert-Contains 'README.md' "当前版本：$version"
Assert-Contains 'source/BUILD.txt' "MouseDesktopGestures $version"
Assert-Contains '使用说明.txt' "鼠标桌面手势 $version"

New-Item -ItemType Directory -Path $toolsDir, $distDir -Force | Out-Null
function Ensure-Tool([string]$file, [string]$url, [string]$expectedHash, [string]$folder, [string]$exe) {
    $archive = Join-Path $toolsDir $file
    if (-not (Test-Path -LiteralPath $archive)) {
        Write-Host "下载固定版本工具：$file"
        Invoke-WebRequest -Uri $url -OutFile $archive
    }
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) { throw "$file 的 SHA-256 不匹配。" }
    $destination = Join-Path $toolsDir $folder
    if (-not (Test-Path -LiteralPath (Join-Path $destination $exe))) {
        Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force
    }
    $tool = Join-Path $destination $exe
    if (-not (Test-Path -LiteralPath $tool)) { throw "找不到工具：$tool" }
    return $tool
}

$base = Ensure-Tool 'AutoHotkey_2.0.28.zip' 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.28/AutoHotkey_2.0.28.zip' 'B63BE7548792B4AD0DFE424D91CC69376694ED2F758245B7A75A0C77D693B478' 'ahk' 'AutoHotkey64.exe'
$compiler = Ensure-Tool 'Ahk2Exe.zip' 'https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.02a2/Ahk2Exe1.1.37.02a2.zip' 'C29B8C3A5124850D79FC9E66E2CA79677C377D7F31631AD3022BA159C5D9E3BE' 'compiler' 'Ahk2Exe.exe'
$source = Join-Path $root 'source/MouseDesktopGestures.ahk'
foreach ($name in @('MouseDesktopGestures.ahk', 'UiTheme.ahk', 'Json.ahk')) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root "source/$name"))
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        throw "$name 必须使用带 BOM 的 UTF-8 编码。"
    }
}

$output = Join-Path $distDir 'MouseDesktopGestures.exe'
$arguments = @('/in', "`"$source`"", '/out', "`"$output`"", '/base', "`"$base`"", '/compress', '0', '/silent')
$build = Start-Process -FilePath $compiler -ArgumentList $arguments -WorkingDirectory (Join-Path $root 'source') -PassThru -Wait -WindowStyle Hidden
if ($build.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw "编译失败，退出码 $($build.ExitCode)。" }
$fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($output).FileVersion
if ($fileVersion -ne $version) { throw "EXE 版本 $fileVersion 与 VERSION $version 不一致。" }

$scratch = Join-Path $distDir ("self-test-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $scratch | Out-Null
$stdout = Join-Path $scratch 'stdout.txt'
$stderr = Join-Path $scratch 'stderr.txt'
$test = Start-Process -FilePath $output -ArgumentList @('--self-test', "`"$scratch`"") -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if ($test.ExitCode -ne 0) {
    Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
    throw "内置自检失败，退出码 $($test.ExitCode)；诊断保存在 $scratch。"
}
Write-Host ((Get-Content -LiteralPath $stdout -Raw -Encoding UTF8).Trim())
$template = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath (Join-Path $root 'config.default.json') -Raw -Encoding UTF8))
$generated = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath (Join-Path $scratch 'config.json') -Raw -Encoding UTF8))
if (-not [System.Text.Json.Nodes.JsonNode]::DeepEquals($template, $generated)) {
    throw 'config.default.json 与程序内置默认值不一致。'
}
if ($InstanceStress) { & (Join-Path $PSScriptRoot 'test-instance.ps1') -Executable $output -Iterations 30 }

if ($UpdateTrackedExe) {
    Copy-Item -LiteralPath $output -Destination (Join-Path $root 'MouseDesktopGestures.exe') -Force
}

if ($Package) {
    $stage = Join-Path $distDir "MouseDesktopGestures-$version-windows-x64"
    $stageFull = [IO.Path]::GetFullPath($stage)
    $distFull = [IO.Path]::GetFullPath($distDir)
    if (-not $stageFull.StartsWith($distFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw '打包目录不在 dist 内。'
    }
    if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
    New-Item -ItemType Directory -Path $stageFull | Out-Null
    foreach ($item in @('MouseDesktopGestures.exe', 'README.md', '使用说明.txt', 'VERSION', 'LICENSE')) {
        $from = if ($item -eq 'MouseDesktopGestures.exe') { $output } else { Join-Path $root $item }
        Copy-Item -LiteralPath $from -Destination (Join-Path $stageFull $item)
    }
    # 发布包只从明确批准的文件清单复制，避免临时放进素材或源码目录的私人文件随包发布。
    $releaseFiles = @(
        'assets/app-icon.png',
        'assets/app.ico',
        'assets/icon-prompt.txt',
        'licenses/AutoHotkey-GPL-2.0.txt',
        'source/AutoHotkey-v2.0.28-source.zip',
        'source/BUILD.txt',
        'source/Json.ahk',
        'source/MouseDesktopGestures.ahk',
        'source/UiTheme.ahk'
    )
    foreach ($relativePath in $releaseFiles) {
        $destination = Join-Path $stageFull $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $relativePath) -Destination $destination
    }
    Copy-Item -LiteralPath (Join-Path $root 'config.default.json') -Destination (Join-Path $stageFull 'config.json')
    $zip = Join-Path $distDir "MouseDesktopGestures-$version-windows-x64.zip"
    Compress-Archive -LiteralPath $stageFull -DestinationPath $zip -Force
    $hashLines = foreach ($artifact in @($output, $zip)) {
        $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $(Split-Path -Leaf $artifact)"
    }
    Set-Content -LiteralPath (Join-Path $distDir 'SHA256SUMS') -Value $hashLines -Encoding ascii
    Write-Host "已生成：$zip"
}

Write-Host "构建和验证通过：$version"
