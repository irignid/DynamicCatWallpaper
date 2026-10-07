$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskName = 'Cat Dynamic Wallpaper'
$vbs      = Join-Path $root 'run-hidden.vbs'
$user     = "$env:USERDOMAIN\$env:USERNAME"

$action    = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`"" -WorkingDirectory $root
$repeat    = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon     = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon, $repeat) -Settings $settings -Principal $principal -Force | Out-Null
} catch {
    Write-Host 'Could not add the at-logon trigger without admin rights; using the 5-minute repeat only.'
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $repeat -Settings $settings -Principal $principal -Force | Out-Null
}

Start-ScheduledTask -TaskName $taskName
Write-Host "Installed. The wallpaper is checked every 5 minutes and at logon."
Write-Host "Keep this folder where it is - the task runs the scripts from here."
