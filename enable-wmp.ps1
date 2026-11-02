$log = "D:\dev\PingIsland\enable-wmp.log"
"=== enabling WindowsMediaPlayer feature ===" | Out-File $log
$out = dism /online /enable-feature /featurename:WindowsMediaPlayer /all /norestart 2>&1
$out | Out-File $log -Append
"=== state after ===" | Out-File $log -Append
dism /online /get-features /format:table 2>&1 |
  Select-String -Pattern 'WindowsMediaPlayer|MediaPlayback' |
  ForEach-Object { $_.Line } | Out-File $log -Append
"=== done ===" | Out-File $log -Append
