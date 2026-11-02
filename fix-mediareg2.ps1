$log = "D:\dev\PingIsland\fix-mediareg2.log"
# 64 位视图
$paths = @(
  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\WindowsFeatures",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Setup\WindowsFeatures"
)
foreach ($p in $paths) {
  try {
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "WindowsMediaVersion" -Value 1 -Type DWord
    $v = (Get-ItemProperty -Path $p -Name "WindowsMediaVersion").WindowsMediaVersion
    "OK 64/32 view: $p = $v" | Out-File $log -Append
  } catch { "FAILED ${p}: $_" | Out-File $log -Append }
}
# 列出全部 Media 相关可选功能状态
"=== optional features (media) ===" | Out-File $log -Append
try {
  dism /online /get-features /format:table 2>&1 |
    Select-String -Pattern 'media' |
    ForEach-Object { $_.Line } | Out-File $log -Append
} catch { "dism failed: $_" | Out-File $log -Append }
"=== done ===" | Out-File $log -Append
