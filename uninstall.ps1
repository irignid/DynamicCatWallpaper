$taskName = 'Cat Dynamic Wallpaper'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host 'Scheduled task removed. Your current wallpaper stays as it is.'
} else {
    Write-Host 'Nothing to remove.'
}
$cache = Join-Path $env:LOCALAPPDATA 'CatWallpaper'
if (Test-Path $cache) { Remove-Item $cache -Recurse -Force }
