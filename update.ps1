<#
.SYNOPSIS
	Auto update script based on chocolatey
.DESCRIPTION
	Checks for outdated packages using chocolatey, and asks user for confirmation whether or not to install the upgrade.
	If the script is not detected in task scheduler, the user will be given the choise to add it to task scheduler automatically,
	Scheduling the script will launch the script on login, in minimized state.
.NOTES
  	Version:        1.0
  	Author:         Jakob Sjaelland
  	Creation Date:  08-05-2018
#>

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
		Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -executionpolicy bypass -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
		Exit
	}
}

# Ask if script is not currently scheduled, then based on user input setup task scheduler
if (!(Get-ScheduledTask -TaskName "Chocolatey update" -ErrorAction SilentlyContinue)) {
	Write-Host "Task scheduler not setup, adding will allow this script to autorun on startup"
	$setup_schedule = Read-Host("would you like to add it to task scheduler? [Y]es/[N]o")
	if($setup_schedule -eq "y" -or $setup_schedule -eq "yes") {
		$TaskArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -file " + '"' + "$PSScriptRoot\update.ps1" + '"'
		$TaskAction = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $TaskArg
		$TaskTrigger = New-ScheduledTaskTrigger -AtLogOn
		$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd  
		$User = "$env:USERDOMAIN\$env:USERNAME"
		$Description = "Chocolatey script, which check for updates and asks user for confirmation"

		Register-ScheduledTask -Action $TaskAction -Trigger $Tasktrigger -Settings $TaskSettings -TaskName "Chocolatey update" -Description $Description -User $User -RunLevel Highest
	}
}

# Make sure internet connection is available
$ping = new-object system.net.networkinformation.ping
$max_attempts = 10
$response = $ping.send("8.8.8.8")
while ($response.status -ne "Success") {
	if($max_attempts -eq 0) {
		exit
	}
	Start-Sleep -Seconds 5
	$response = $ping.send("8.8.8.8")

	$max_attempts = $max_attempts - 1
}

# Check for outdated packages using chocolatey
Write-Host "---------------------------------"
Write-Host "Checking for outdated packages..."
Write-Host "---------------------------------"
$outdated_packages = (choco outdated -r)
if ($outdated_packages) {
	$packages = foreach ($string in $outdated_packages) {
		Write-Host $string
	
		[PSCustomObject]@{
			name = $string.Split('|')[0]
			current_version = $string.Split('|')[1]
			new_version = $string.Split('|')[2]
			pinned = $string.Split('|')[3]
		}
	}
	# Install new packages, based on user input
	foreach($package in $packages) {
		$update = Read-Host("Do you want to upgrade " + $package.name + "? [Y]es/[N]o or [A]ll")
		$update = $update.ToLower()

		if ($update -eq "y" -or $update -eq "yes") {
			Write-Host ("Upgrading " + $package.name + "...")
			choco upgrade $package.name -y --limit-output --no-progress
		} elseif ($update -eq "a" -or $update -eq "all") {
			Write-Host "Upgrading all packages..."
			foreach ($package in $packages) {
				if($package.pinned -eq "false") {
					choco upgrade $package.name -y --limit-output --no-progress
				}
			}
			break
		}
	}
}

Write-Host -NoNewLine "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")