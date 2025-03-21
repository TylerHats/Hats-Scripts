# PC Setup Script - Tyler Hatfield - v1.21
# Elevation check
$IsElevated = [System.Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544'
if (-not $IsElevated) {
    Write-Host "This script requires elevation. Please grant Administrator permissions." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Script setup
$failedResize = 0
$failedColor = 0
try {
	$dWidth = (Get-Host).UI.RawUI.BufferSize.Width
	$dHeight = 40
	$rawUI = $Host.UI.RawUI
	$newSize = New-Object System.Management.Automation.Host.Size ($dWidth, $dHeight)
	$rawUI.WindowSize = $newSize
} catch {
	$failedResize = 1
}
try {
	$host.UI.RawUI.BackgroundColor = "Black"
} catch {
	$failedColor = 1
}
Clear-Host
$Host.UI.RawUI.WindowTitle = "Hat's Setup Script"
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$logPathName = "PCSetupScriptLog.txt"
$logPath = Join-Path $DesktopPath $logPathName
$WUSPath = Join-Path -Path $PSScriptRoot -ChildPath 'Windows Update Script.ps1'
$functionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Script Functions.ps1'
. "$functionPath"
try {
	$serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
} catch {
	$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
}
if ($failedResize -eq 1) {Log-Message "Failed to resize window." "Error"}
if ($failedColor -eq 1) {Log-Message "Failed to change background color." "Error"}

# Check script version against remote
$currentVersion = "1.15.1"
$skipUpdate = 0
Try {
	$remoteRequest = Invoke-WebRequest -Uri "https://hatsthings.com/HatsScriptsVersion.txt"
} catch {
	Log-Message "Unable to determine remote version, skipping self update check."
	$skipUpdate = 1
}
if ($skipUpdate -ne 1) {
	$remoteVersion = $remoteRequest.Content
	if ($currentVersion -eq $remoteVersion) {
		Log-Message "The script is up to date. (Version $currentVersion)" "Info"
	} else {
		Log-Message "Updating and relaunching the script... (Current Version: $currentVersion - Remote Version: $remoteVersion)" "Info"
		$sourceURL = "https://github.com/TylerHats/Hats-Scripts/releases/latest/download/Hats-Setup-Script-v$remoteVersion.exe"
		$shell = New-Object -ComObject Shell.Application
		$downloadsFolder = $shell.Namespace('shell:Downloads').Self.Path
		$outputPath = "$downloadsFolder\Hats-Setup-Script-v$remoteVersion.exe"
		Try {
			Invoke-WebRequest -Uri $sourceURL -OutFile $outputPath *>&1
		} catch {
			Log-Message "Failed to download update, please update manually." "Error"
			Pause
			Exit
		}
		# Cleanup and exit current script, then launch updated script
		$folderToDelete = "$PSScriptRoot"
		$deletionCommand = "Start-Sleep -Seconds 2; Remove-Item -Path '$folderToDelete' -Recurse -Force; Add-Content -Path '$logPath' -Value 'Script self cleanup completed during self update'; Start-Process '$outputPath'"
		Start-Process powershell.exe -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-Command", $deletionCommand
		exit 0
	}
}

# Set time zone and sync
Log-Message "Setting Time Zone to Eastern Standard Time..."
Set-TimeZone -Name "Eastern Standard Time" | Out-File -Append -FilePath $logPath
if ((Get-Service -Name w32time).Status -ne 'Running') {
    Start-Service -Name w32time | Out-File -Append -FilePath $logPath
}
w32tm /resync | Out-File -Append -FilePath $logPath

# Setup prerequisites and start Windows updates
Log-Message "Starting Windows Updates in the Background..."
Log-Message "Install Cumulative updates for Windows? (These can be very slow) (y/N):" "Prompt"
$env:installCumulativeWU = Read-Host
$ProgressPreference = 'SilentlyContinue'
Install-PackageProvider -Name NuGet -Force | Out-File -Append -FilePath $logPath
Install-Module -Name PSWindowsUpdate -Force | Out-File -Append -FilePath $logPath
try {
	Set-DODownloadMode -DownloadMode 3 -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath
} catch {
	Log-Message "Delivery Optimization mode setting failed, continuing with defaults..." "Error"
}
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass", "-File `"$WUSPath`""

# Set/Create local admin account
Log-Message "Setup Local Account(s)..."
$RepeatFunction = 1
While ($RepeatFunction -eq 1) {
    Log-Message "Please enter a username or leave blank to skip this section:" "Prompt"
	$AdminUser = Read-Host
	if ($AdminUser -ne "") {
		Log-Message "Please enter a password (can be empty):" "Prompt"
		$AdminPass = Read-Host
		$UExists = Get-LocalUser -Name "$AdminUser" -ErrorAction SilentlyContinue
		if (-not $UExists) {
			Log-Message "The specified user does not exist, create account now? (y/N):" "Prompt"
			$MakeUser = Read-Host
			if ($MakeUser -eq "y" -or $MakeUser -eq "Y") {
				Net User "$AdminUser" "$AdminPass" /add | Out-File -Append -FilePath $logPath
			} else {
				Log-Message "Skipping account creation." "Skip"
			}
		} else {
			Log-Message "Update the user's password? (y/N):" "Prompt"
			$UpdateUser = Read-Host
			if ($UpdateUser.ToLower() -eq "y" -or $UpdateUser.ToLower() -eq "yes") {
				Net User "$AdminUser" "$AdminPass" | Out-File -Append -FilePath $logPath
			}
		}
		$LocalUserCheck = "$env:COMPUTERNAME\$AdminUser"
		$IsAdmin = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $LocalUserCheck }
		if ($UExists -and -not $IsAdmin) {
			Log-Message "The specified user is not a local admin, elevate now? (y/N):" "Prompt"
			$MakeAdmin = Read-Host
			if ($MakeAdmin -eq "y" -or $MakeAdmin -eq "Y") {
				Net Localgroup Administrators "$AdminUser" /add | Out-File -Append -FilePath $logPath
			} else {
				Log-Message "Skipping account elevation." "Skip"
			}
		} elseif ($UExists -and $IsAdmin) {
			Log-Message "Skipping account elevation, user account is already a local administrator." "Skip"
		}
		Log-Message "Repeat this segment to add, edit or test another user account? (y/N):" "Prompt"
		$RFQ = Read-Host
		if (-not ($RFQ.ToLower() -eq "y" -or $RFQ.ToLower() -eq "yes")) {
			$RepeatFunction = 0
		}
	} else {
		Log-Message "Skipping account management." "Skip"
		$RepeatFunction = 0
	}
}

# Update WinGet and set defaults
Log-Message "Updating WinGet and App Installer..."
Set-WinUserLanguageList -Language en-US -force *>&1 | Out-File -Append -FilePath $logPath
$ProgressPreference = 'Continue'
winget source add --name HatsRepoAdd https://cdn.winget.microsoft.com/cache *>&1 | Out-File -Append -FilePath $logPath
winget Source Update --disable-interactivity *>&1 | Out-File -Append -FilePath $logPath
if ($LASTEXITCODE -ne 0) { winget Source Update *>&1 | Out-File -Append -FilePath $logPath }
winget Upgrade --id Microsoft.Appinstaller --accept-package-agreements --accept-source-agreements *>&1 | Out-File -Append -FilePath $logPath
$maxWaitSeconds = 180    # 3 minutes
$waitIntervalSeconds = 30
$elapsedSeconds = 0
$WaitInstall = "blank"
# Loop while msiexec.exe is running
while (Get-Process -Name msiexec -ErrorAction SilentlyContinue) {
	if ($WaitInstall -eq "blank") {
    	Log-Message "Another installation is in progress. Would you like to wait or continue? (c/W):" "Prompt"
		$WaitInstall = Read-Host
	}
	if ($WaitInstall.ToLower() -eq "c" -or $WaitInstall.ToLower() -eq "continue") {
		Log-Message "Ignoring background installation and continuing..." "Info"
		break
	}
	Log-Message "Waiting $waitIntervalSeconds and checking again..." "Info"
    Start-Sleep -Seconds $waitIntervalSeconds
    $elapsedSeconds += $waitIntervalSeconds
    if ($elapsedSeconds -ge $maxWaitSeconds) {
        Log-Message "Waited for $maxWaitSeconds seconds and the installer still has not cleared. Would you like to kill MSIEXEC.exe? (y/N):" "Prompt"
        $KillMSIE = Read-Host
		if ($KillMSIE.ToLower() -eq "y" -or $KillMSIE.ToLower() -eq "yes") {
			Log-Message "Killing MSIEXEC.exe and continuing WinGet updates..." "Info"
			try {Get-Process -Name "msiexec" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath} catch {Log-Message "Failed to kill process MSIEXEC.exe, continuing..." "Error"}
		} else {
			Log-Message "Ignoring background installation and continuing WinGet updates..." "Info"
		}
		break
    }
}

# Remove common Windows bloat
Log-Message "Would you like to remove common Windows bloat programs? (y/N):" "Prompt"
$RemoveBloat = Read-Host
if ($RemoveBloat.ToLower() -eq "y" -or $RemoveBloat.ToLower() -eq "yes") {
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*bingfinance*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*bingnews*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*bingsports*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*gethelp*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*getstarted*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*mixedreality*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*people*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*solitaire*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*wallet*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*windowsfeedback*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*windowsmaps*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*xbox*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
	Get-AppxPackage -AllUsers -PackageTypeFilter Bundle -Name "*zunevideo*" | Remove-AppxPackage -AllUsers -Verbose 4>&1 | Out-File -Append -FilePath $logPath
} else {
	Log-Message "Skipping bloat removal." "Skip"
}

# Install programs based on selections, prepare Windows "Form"
Log-Message "Preparing Software List..."
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Program Selection List'
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#2f3136")
$form.Size = New-Object System.Drawing.Size(400, 500)
$form.StartPosition = 'CenterScreen'

# Dynamic size based on number of programs
$checkboxHeight = 30    # Height of each checkbox
$progressBarHeight = 70 # Height of the progress bar
$buttonHeight = 80      # Height of the OK button
$labelHeight = 30       # Height of text labels
$padding = 20           # Padding around the elements

<#
Program list using multiple variable per program in an array:
Name = The Program's display name, should be human readable
WingetID = If the program is to be installed using Winget, this must be filled out
Type = Program type, current options are: Winget, MSOffice
#>
$programs = @(
    @{ Name = 'Acrobat Reader'; WingetID = 'Adobe.Acrobat.Reader.64-bit'; Type = 'Winget' },
	@{ Name = 'Creative Cloud'; WingetID = 'Adobe.CreativeCloud'; Type = 'Winget' },
    @{ Name = 'Google Chrome'; WingetID = 'Google.Chrome'; Type = 'Winget' },
    @{ Name = 'Firefox'; WingetID = 'Mozilla.Firefox'; Type = 'Winget' },
    @{ Name = '7-Zip'; WingetID = '7zip.7zip'; Type = 'Winget' },
    @{ Name = 'Google Drive'; WingetID = 'Google.Drive'; Type = 'Winget' },
    @{ Name = 'Dropbox'; WingetID = 'Dropbox.Dropbox'; Type = 'Winget' },
	@{ Name = 'VLC Media Player'; WingetID = 'VideoLAN.VLC'; Type = 'Winget' },
    @{ Name = 'Zoom'; WingetID = 'Zoom.Zoom'; Type = 'Winget' },
    @{ Name = 'Outlook Classic'; WingetID = ''; Type = 'MSOutlook' },
    @{ Name = 'Microsoft Teams (In testing)'; WingetID = ''; Type = 'Teams' },
	@{ Name = 'Microsoft Office (64-Bit)'; WingetID = ''; Type = 'MSOffice' }
)

# Adjust form size based on the number of programs
$formHeight = ($programs.Count * $checkboxHeight) + $progressBarHeight + $buttonHeight + ($padding * 2) + $labelHeight
$form.Size = New-Object System.Drawing.Size(400, $formHeight)
$form.StartPosition = 'CenterScreen'

# Prepare Program Checkboxes
$checkboxes = @{ }
$y = 20
$label = New-Object System.Windows.Forms.Label
$label.Text = "Programs:"
$label.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#d9d9d9")
$label.Location = New-Object System.Drawing.Point(20, $y)
$label.AutoSize = $true
$form.Controls.Add($label)
$y += $labelHeight
foreach ($program in $programs) {
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Location = New-Object System.Drawing.Point(20, $y)
    $checkbox.Text = $program.Name
	$checkbox.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#d9d9d9")
    $checkbox.AutoSize = $true
    $form.Controls.Add($checkbox)
    $checkboxes[$program.Name] = $checkbox
    $y += $checkboxHeight
}

$outlookCheckbox = $checkboxes["Outlook Classic"]
$officeCheckbox = $checkboxes["Microsoft Office (64-Bit)"]

# Add an event handler for the Outlook checkbox:
$outlookCheckbox.Add_CheckedChanged({
    if ($outlookCheckbox.Checked) {
        # When Outlook is checked, disable and uncheck Microsoft Office
        $officeCheckbox.Enabled = $false
        $officeCheckbox.Checked = $false
    }
    else {
        # When Outlook is unchecked, re-enable Microsoft Office
        $officeCheckbox.Enabled = $true
    }
})

# Add an event handler for the Microsoft Office checkbox:
$officeCheckbox.Add_CheckedChanged({
    if ($officeCheckbox.Checked) {
        # When Microsoft Office is checked, disable and uncheck Outlook
        $outlookCheckbox.Enabled = $false
        $outlookCheckbox.Checked = $false
    }
    else {
        # When Microsoft Office is unchecked, re-enable Outlook
        $outlookCheckbox.Enabled = $true
    }
})

# Add progress bar to GUI
$progressBar = New-Object System.Windows.Forms.ProgressBar
$y += 10
$progressBar.Location = New-Object System.Drawing.Point(20, $y)
$progressBar.Style = "Continuous"
$progressBar.Size = New-Object System.Drawing.Size(340, 20)
$progressBar.Minimum = 0
$progressBar.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#6f1fde")
$form.Controls.Add($progressBar)

# Add OK button
$okButton = New-Object System.Windows.Forms.Button
$y += 50
$okButton.Location = New-Object System.Drawing.Point(150, $y)
$okButton.Size = New-Object System.Drawing.Size(75, 30)
$okButton.Text = "OK"
$okButton.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#d9d9d9")
$form.Controls.Add($okButton)

# Define a function to handle the OK button click
$okButton.Add_Click({
    # Disable OK button to prevent further clicks
    $okButton.Enabled = $false

    # Install selected programs
    $selectedPrograms = $checkboxes.GetEnumerator() | Where-Object { $_.Value.Checked } | ForEach-Object { $_.Key }
    $totalPrograms = $selectedPrograms.Count
    if ($totalPrograms -eq 0) {
        Log-Message "No programs selected for installation." "Skip"
        $form.Close()
        return
    }

    # Set progress bar maximum to match selected programs
    $progressBar.Maximum = $totalPrograms

    # Install programs and update progress bar
    $progressBar.Value = 0
    foreach ($programName in $selectedPrograms) {
        $program = $programs | Where-Object { $_.Name -eq $programName }
        if ($program.Type -eq "MSOffice") {
			try {
			Log-Message "Installing Microsoft Office (x64)..." "Info"
			$workingDir = Join-Path -Path "$PSScriptRoot" -ChildPath "OfficeODT"
			if (-Not (Test-Path $workingDir)) { New-Item -ItemType Directory -Path $workingDir }
			$odtUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_18526-20146.exe"
			$odtExe = "$workingDir\OfficeDeploymentTool.exe"
			if (-Not (Test-Path $odtExe)) {
			    Log-Message "Downloading Office Deployment Tool..." "Info"
			    try {Invoke-WebRequest -Uri $odtUrl -OutFile $odtExe *>&1 | Out-File -Append -FilePath $logPath} catch {Log-Message "ODT download failed, check your internet connection." "Error"}
				Unblock-File -Path $odtExe *>&1 | Out-File -Append -FilePath $logPath
			}
			Log-Message "Extracting Office Deployment Tool..." "Info"
			Start-Process -FilePath $odtExe -ArgumentList "/extract:`"$workingDir`"", "/quiet" -Wait
			$configXml = @'
<Configuration>
  <Add OfficeClientEdition="64" Channel="Monthly">
    <Product ID="O365BusinessRetail">
      <Language ID="en-us" />
    </Product>
  </Add>
  <Display Level="Basic" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1"/>
</Configuration>
'@
			$configFile = "$workingDir\officeconfiguration.xml"
			$configXml | Out-File -FilePath $configFile -Encoding ascii
			Start-Process -FilePath "$workingDir\setup.exe" -ArgumentList "/configure `"$configFile`"" -Wait
			Log-Message "Microsoft Office: Installed successfully." "Success"
			 } catch {
				Log-Message "Microsoft Office: Installation failed, please review the log." "Error"
			 }
		} elseif ($program.Type -eq "MSOutlook") {
			try {
			Log-Message "Installing Microsoft Outlook (Classic)..." "Info"
			$workingDir = Join-Path -Path "$PSScriptRoot" -ChildPath "OfficeODT"
			if (-Not (Test-Path $workingDir)) { New-Item -ItemType Directory -Path $workingDir }
			$odtUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_18526-20146.exe"
			$odtExe = "$workingDir\OfficeDeploymentTool.exe"
			if (-Not (Test-Path $odtExe)) {
			    Log-Message "Downloading Office Deployment Tool..." "Info"
			    try {Invoke-WebRequest -Uri $odtUrl -OutFile $odtExe *>&1 | Out-File -Append -FilePath $logPath} catch {Log-Message "ODT download failed, check your internet connection." "Error"}
				Unblock-File -Path $odtExe *>&1 | Out-File -Append -FilePath $logPath
			}
			Log-Message "Extracting Office Deployment Tool..." "Info"
			Start-Process -FilePath $odtExe -ArgumentList "/extract:`"$workingDir`"", "/quiet" -Wait
			$configXml = @'
<Configuration>
  <Add OfficeClientEdition="64" Channel="Monthly">
    <Product ID="OutlookRetail">
      <Language ID="en-us" />
    </Product>
  </Add>
  <Display Level="Basic" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1"/>
</Configuration>
'@
			$configFile = "$workingDir\outlookconfiguration.xml"
			$configXml | Out-File -FilePath $configFile -Encoding ascii
			Start-Process -FilePath "$workingDir\setup.exe" -ArgumentList "/configure `"$configFile`"" -Wait
			Log-Message "Microsoft Outlook: Installed successfully." "Success"
			 } catch {
				Log-Message "Microsoft Outlook: Installation failed, please review the log." "Error"
			}
		} elseif ($program.Type -eq "Teams") {
			Log-Message "Installing Microsoft Teams..."
			try {
				#Teams Installation code
				$bootstrapperURL = "https://statics.teams.cdn.office.net/production-teamsprovision/lkg/teamsbootstrapper.exe"
				$teamsEXE = "$workingDir\teamsbootstrapper.exe"
				Log-Message "Downloading Teams Bootstrapper..." "Info"
			    try {Invoke-WebRequest -Uri $bootstrapperURL -OutFile $teamsEXE *>&1 | Out-File -Append -FilePath $logPath} catch {Log-Message "Bootstrapper download failed, check your internet connection." "Error"}
				Unblock-File -Path $teamsEXE *>&1 | Out-File -Append -FilePath $logPath
				Start-Process -FilePath "$teamsEXE" -ArgumentList "-p" -Wait
			} catch {
				Log-Message "Microsoft Teams installation failed." "Error"
			}
		} elseif ($program -ne $null) {
			$maxWaitSeconds = 60    # 1 minute
			$waitIntervalSeconds = 20
			$elapsedSeconds = 0
			$WaitInstall = "blank"
			# Loop while msiexec.exe is running
			while (Get-Process -Name msiexec -ErrorAction SilentlyContinue) {
<#				if ($WaitInstall -eq "blank") {
			 	   	Log-Message "Another installation is in progress. Would you like to wait or continue? (c/W):" "Prompt"
					$WaitInstall = Read-Host
				}
				if ($WaitInstall.ToLower() -eq "c" -or $WaitInstall.ToLower() -eq "continue") {
					Log-Message "Ignoring background installation and continuing..." "Info"
					break
				}
				Log-Message "Waiting $waitIntervalSeconds seconds and checking again..." "Info"
			    Start-Sleep -Seconds $waitIntervalSeconds
			    $elapsedSeconds += $waitIntervalSeconds
			    if ($elapsedSeconds -ge $maxWaitSeconds) {
			        Log-Message "Waited for $maxWaitSeconds seconds and the installer still has not cleared. Would you like to kill MSIEXEC.exe? (y/N):" "Prompt"
			        $KillMSIE = Read-Host
					if ($KillMSIE.ToLower() -eq "y" -or $KillMSIE.ToLower() -eq "yes") {
						Log-Message "Killing MSIEXEC.exe and continuing WinGet updates..." "Info"
						try {Get-Process -Name "msiexec" -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath} catch {Log-Message "Failed to kill process MSIEXEC.exe, continuing..." "Error"}
					} else {
						Log-Message "Ignoring background installation and continuing WinGet program install..." "Info"
					}
					break
 			   } #>
				#Log-Message "Killing MSIEXEC.exe and continuing WinGet installations..." "Info"
				Get-Process -Name "msiexec" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue *>&1 | Out-File -Append -FilePath $logPath
				break
			}
            Log-Message "Installing $($program.Name)..."
            try {
                # Corrected WinGet command execution
                $wingetArgs = @(
                    "install",
                    "-e",  # Exact match flag
                    "--id", $program.WingetID,
                    "--scope", "machine",
                    "--accept-package-agreements",
                    "--accept-source-agreements"
                )

                # Use Start-Process with the correct arguments
                $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -PassThru -Wait -WindowStyle Hidden

                # Capture the result
                if ($process.ExitCode -eq 0) {
                    $message = "$($program.Name): Installed successfully."
                    Log-Message $message "Success"
					Get-Process -Name "msiexec" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue *>&1 | Out-File -Append -FilePath $logPath

                } else {
                    $message = "$($program.Name): Installation failed with exit code $($process.ExitCode)."
                    Log-Message $message "Error"
                }
            } catch {
                $message = "$($program.Name): Installation failed. Error: $_"
                Log-Message $message "Error"
            }
        }
        $progressBar.Value += 1
        # Start-Sleep -Milliseconds 200 # Simulate progress bar movement
    }

    # Close the form once installation is complete
    $form.Close()
})

# Show the GUI
$form.ShowDialog() | Out-null

# Rename PC and join to domain (if needed)
$DNRetry = "y"
while ($DNRetry.ToLower() -eq "y" -or $DNRetry.ToLower() -eq "yes") {
	$DNRetry = "n"
	Log-Message "The PC is currently named: $env:computername"
	Log-Message "Would you like to change the PC name? (y/N):" "Prompt"
	$Rename = Read-Host
	if ($Rename.ToLower() -eq "y" -or $Rename.ToLower() -eq "yes") {
	    Log-Message "The serial number is: $serialNumber"
    	Log-Message "Enter the new PC name and press Enter:" "Prompt"
    	$PCName = Read-Host
    	Log-Message "Would you like to join this PC to an Active Directory Domain? (y/N):" "Prompt"
		$Domain = Read-Host
		if ($Domain.ToLower() -eq "y" -or $Domain.ToLower() -eq "yes") {
    	    Log-Message "Enter the domain address and press Enter (Include the suffix, Ex: .local):" "Prompt"
			$DomainName = Read-Host
			$DomainCredential = Get-Credential -Message "Enter credentials with permission to add this device to $($DomainName):"
			try {
				Add-Computer -DomainName $DomainName -NewName $PCName -Credential $DomainCredential -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath
				Log-Message "Domain joining and PC renaming successful." "Success"
			} catch {
				Log-Message "Domain joining and/or PC naming failed, please verify the name is <15 digits and contains no forbidden characters, and credentials are correct." "Error"
				Log-Message "Retry segment? (y/N):" "Prompt"
				$DNRetry = Read-Host
			}
		} else {
			try {
				Rename-Computer -NewName $PCName -Force -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath
				Log-Message "PC renaming successful." "Success"
			} catch {
				Log-Message "PC renaming failed, please verify the name is <15 digits and contains no forbidden characters." "Error"
				Log-Message "Retry segment? (y/N):" "Prompt"
				$DNRetry = Read-Host
			}
		}
	} else {
	    Log-Message "Would you like to join this PC to an Active Directory Domain? (y/N):" "Prompt"
		$Domain = Read-Host
		if ($Domain.ToLower() -eq "y" -or $Domain.ToLower() -eq "yes") {
   	    	Log-Message "Enter the domain address and press Enter (Include the suffix, Ex: .local):" "Prompt"
			$DomainName = Read-Host
			$DomainCredential = Get-Credential -Message "Enter credentials with permission to add this device to $($DomainName):"
			try {
				Add-Computer -DomainName $DomainName -Credential $DomainCredential -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath
				Log-Message "Domain joining successful." "Success"
			} catch {
				Log-Message "Domain joining failed, verify credentials are correct." "Error"
				Log-Message "Retry segment? (y/N):" "Prompt"
				$DNRetry = Read-Host
			}
		}
	}
	if (-not ($Domain.ToLower() -eq "y" -or $Domain.ToLower() -eq "yes")) {
		Log-Message "Would you like to launch the EntraID joining dialog? (y/N):" "Prompt"
		$Entra = Read-Host
		if ($Entra.ToLower() -eq "y" -or $Entra.ToLower() -eq "yes") {
			Log-Message "Launching EntraID dialog..." "Info"
			try {
				dsregcmd.exe /join -ErrorAction Stop *>&1 | Out-File -Append -FilePath $logPath
			} catch {
				Log-Message "Failed to launch EntraID dialog, ensure the device is not joined to a domain and is Windows 10/11 Pro" "Error"
			}
		}
	}
}

# Final setup options
$regPathNumLock = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"
if (Test-Path $regPathNumLock) {
    # Set the InitialKeyboardIndicators value to 2 (Enables numlock by default)
    Set-ItemProperty -Path $regPathNumLock -Name "InitialKeyboardIndicators" -Value "2"
    Log-Message "Enabled NUM Lock at boot by default." "Success"
} else {
    Log-Message "Registry path $regPathNumLock does not exist." "Error"
}

# Reminders/Closing
Log-Message "Script setup is complete!"
Log-Message "Confirm updates have completed in the minimized window and restart to apply updates, PC name change and domain joining if needed."
Log-Message "Press enter to exit the script." "Success"
Read-Host

# Post execution cleanup
$cleanupCheckValue = "ScriptFolderIsReadyForCleanup"
$logContents = Get-Content -Path $logPath
if ($logContents -contains $cleanupCheckValue) {
	[System.Environment]::SetEnvironmentVariable("installCumulativeWU", $null, [System.EnvironmentVariableTarget]::Machine)
	$folderToDelete = "$PSScriptRoot"
	$deletionCommand = "Start-Sleep -Seconds 2; Remove-Item -Path '$folderToDelete' -Recurse -Force; Add-Content -Path '$logPath' -Value 'Script self cleanup completed'"
	Start-Process powershell.exe -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-Command", $deletionCommand
	exit 0
} else {
	Add-Content -Path $logPath -Value $cleanupCheckValue
	exit 0
}