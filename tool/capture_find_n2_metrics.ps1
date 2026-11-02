[CmdletBinding()]
param(
    [string]$Serial,
    [string]$OutputRoot = (Join-Path $PSScriptRoot "..\output\find-n2")
)

$ErrorActionPreference = "Stop"
$packageName = "com.nihaisha.nihaisha_app"

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -eq $adbCommand) {
    throw "未找到 adb。请先安装 Android platform-tools，并将 adb 加入 PATH。"
}
$adb = $adbCommand.Source

function Invoke-AdbText {
    param([string[]]$Arguments)

    $result = & $script:adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ADB 命令失败：adb $($Arguments -join ' ')；$($result -join '; ')"
    }
    return (($result | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $deviceRows = & $adb devices
    if ($LASTEXITCODE -ne 0) {
        throw "无法读取 adb devices。"
    }

    $connected = @(
        $deviceRows |
            Where-Object { $_ -match '^\S+\s+device$' } |
            ForEach-Object { ($_ -split '\s+')[0] }
    )
    if ($connected.Count -eq 0) {
        throw "没有已授权的 Android 设备。请连接 Find N2、开启 USB 调试并确认电脑授权。"
    }
    if ($connected.Count -gt 1) {
        throw "检测到多台设备：$($connected -join ', ')。请用 -Serial 指定目标设备。"
    }
    $Serial = $connected[0]
}

$state = Invoke-AdbText -Arguments @("-s", $Serial, "get-state")
if ($state -ne "device") {
    throw "设备 $Serial 当前状态不是 device：$state"
}

$packagePath = Invoke-AdbText -Arguments @("-s", $Serial, "shell", "pm", "path", $packageName)
if (-not $packagePath.StartsWith("package:")) {
    throw "设备上未安装 $packageName。请先安装本轮 Debug APK。"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDirectory = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$metadataPath = Join-Path $runDirectory "device-metadata.json"
$logPath = Join-Path $runDirectory "window-metrics.log"

$metadata = [ordered]@{
    capturedAt = (Get-Date).ToString("o")
    serial = $Serial
    packageName = $packageName
    model = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "getprop", "ro.product.model"))
    manufacturer = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "getprop", "ro.product.manufacturer"))
    androidRelease = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "getprop", "ro.build.version.release"))
    androidSdk = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "getprop", "ro.build.version.sdk"))
    screenSize = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "wm", "size"))
    screenDensity = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "wm", "density"))
    fontScale = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "settings", "get", "system", "font_scale"))
    flutterMetricsFilter = "[WINDOW_METRICS]"
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -Path $metadataPath -Encoding UTF8

Invoke-AdbText -Arguments @("-s", $Serial, "logcat", "-c") | Out-Null

Write-Host "设备：$($metadata.manufacturer) $($metadata.model) / Android $($metadata.androidRelease)"
Write-Host "系统尺寸：$($metadata.screenSize)，密度：$($metadata.screenDensity)，字号：$($metadata.fontScale)"
Write-Host "采集目录：$runDirectory"
Write-Host "现在切换外屏、内屏、半折叠姿态，并操作键盘、相机和文件选择器。"
Write-Host "只保存 [WINDOW_METRICS] 行；按 Ctrl+C 结束采集。"

$script:metricsLineCount = 0
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
try {
    & $adb -s $Serial logcat -v time -s flutter:I 2>&1 |
        ForEach-Object {
            $line = "$_"
            if ($line -match '\[WINDOW_METRICS\]') {
                [System.IO.File]::AppendAllText(
                    $logPath,
                    $line + [Environment]::NewLine,
                    $utf8NoBom
                )
                $script:metricsLineCount++
                Write-Host $line
            }
        }
}
finally {
    $summary = [ordered]@{
        finishedAt = (Get-Date).ToString("o")
        deviceSerial = $Serial
        metricsLineCount = $script:metricsLineCount
        metricsLog = $logPath
        metadata = $metadataPath
        note = "仅包含 [WINDOW_METRICS] 行；截图需单独保存。"
    }
    $summary | ConvertTo-Json -Depth 4 |
        Set-Content -Path (Join-Path $runDirectory "capture-summary.json") -Encoding UTF8

    if ($script:metricsLineCount -eq 0) {
        Write-Warning "没有捕获到 [WINDOW_METRICS] 行。请确认 Debug APK 正在前台运行，再执行一次姿态切换。"
    }
    else {
        Write-Host "已保存 $($script:metricsLineCount) 条窗口指标：$logPath"
    }
}
