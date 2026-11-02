$log = "D:\dev\PingIsland\fix-mediareg.log"
$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\WindowsFeatures"
try {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "WindowsMediaVersion" -Value 1 -Type DWord
    $v = Get-ItemProperty -Path $path -Name "WindowsMediaVersion"
    "OK: WindowsMediaVersion = $($v.WindowsMediaVersion)" | Out-File $log
} catch { "FAILED: $_" | Out-File $log }
