<#
.SYNOPSIS
Manage fan speeds on Dell PowerEdge Servers

.DESCRIPTION
Quick, automated powershell script to test interior temps on a Dell PowerEdge servers
and adjust fan speeds/decibels as necessary. Also logs output to EventLog and
(optionally) a log file for reading into a graphing/monitoring tool.

I use this as a scheduled task that runs ever 10 minutes. It doesn't need any special
permissions - just needs the iDrac to have IPMI enabled, and the IPMITool installed.

I do leverage my SecureTokens module (https://github.com/brsh/SecureTokens) to encrypt
the username and password, but you can hardcode the cleartext user/pass in either the
$IDRACUSER and $IDRACPASSWORD variables defined below, or via to text files saved with
this script (username.txt and password.txt). Note that the SecurTokens can only be
saved/read by the 'current user' on the 'current machine' - so if you run this as a
service account, make sure to log in as the service account to save the tokens.

This script can run from anywhere with network access to the iDrac.

Important variables:
	* $IDRACUSer: the username to use to access the iDrac
		Notes: if you leave the variables blank, the script will:
			1. Try pulling SecureTokens for IPMIUser and IPMIPassword (encrypted);
			2. Try reading from .\username.txt and .\password.txt (plain text);
			3. Fail
	* $IDRACIP: the ip of the iDrac (IPMI over LAN must be enabled)
	* $PathToIPMITool: the path to the directory where ipmitool.exe is located
	* LogFile: the path to a text file for logging
		Notes: If empty, no log will be kept.

Scheduled Task:
	Program to run should be Powershell.exe
	Arguments should be:
		-NonInteractive -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass
			-file "*:\Path\To\Script\fanspeed.ps1"
	(note: that's all one line, just wrapped for reading purposes)

.EXAMPLE
.\fanspeed.ps1 -Verbose

Run this to see what it's doing and if it's working. This will set
the fan speeds (if it's working, of course) and exit

.EXAMPLE
.\fanspeed.ps1

Run this to just set fanspeeds and exit
#>

[CmdletBinding()]
param ()

#Set the ip of your iDrac
[string] $IDRACIP = ''
#Set a User/Password if you don't want to use files or SecureToken
[string] $IDRACUSER = ''
[string] $IDRACPASSWORD = ''

#Change this to *:\Path\Where\IPMITool\Is
[string] $PathToIPMItool = 'C:\Dell\SysMgt\bmc'

# Leave blank to disable monitor log
[string] $LogFile = 'c:\Monitor\fanspeed.log'

[int] $PlanarTemp = 52
[int] $AmbientTemp = 0
[int] $FanSpeed = 8888

[string] $Message = 'Fan Speed v2 Script Start: '
$Message += $(Get-Date).ToString()
$Message += "`r`n`r`n"

New-EventLog -LogName Application -Source 'FanSpeed'-ErrorAction SilentlyContinue

if ($IDRACUSER.Length -eq 0) {
	Write-Verbose "Testing for SecureTokens module"
	if (get-module -ListAvailable -Verbose:$false | Where-Object { $_.Name -match 'SecureToken' }) {
		try {
			write-verbose "  Importing SecureTokens module"
			import-module SecureTokens -force -Verbose:$false -ErrorAction Stop -ArgumentList $true
			try {
				Write-Verbose '    Looking for the IPMIUser SecureToken'
				$IDRACUSER = (Get-SecureToken -Name IPMIUser).Token
				Write-Verbose "      Username: $IDRACUSER"
			} catch {
				Write-Verbose "      Error pulling IPMIUser SecureToken"
				Write-Verbose "      $($_.Exception.Message)"
				$IDRACUSER = ''
			}
			try {
				Write-Verbose '    Looking for the IPMIPassword SecureToken'
				$IDRACPASSWORD = (Get-SecureToken -Name IPMIPassword).Token
				Write-Verbose "      Password: (found)"
			} catch {
				Write-Verbose "      Error pulling IPMIPassword SecureToken"
				Write-Verbose "      $($_.Exception.Message)"
				$IDRACPASSWORD = ''
			}
		} catch {
			Write-Verbose "  Error importing SecureTokens module."
			Write-Verbose "  $($_.Exception.Message)"
		}
	} else {
		Write-Verbose "  SecureTokens module not found"
	}
}

#Local Files if SecureTokens module is not available (or no tokens saved)
if ($IDRACUSER.Length -eq 0) {
	Write-Verbose "Testing for local username file (unencrypted)"
	if (Test-Path '.\username.txt') {
		Write-Verbose "  Local username file found. Pulling username"
		try {
			$IDRACUSER = Get-Content '.\username.txt'
			Write-Verbose "      Username: $IDRACUSER"
		} catch {
			Write-Verbose "    Error pulling username"
			Write-Verbose "    $($_.Exception.Message)"
			$IDRACUSER = ''
		}
	}
}
if ($IDRACPASSWORD.Length -eq 0) {
	Write-Verbose "Testing for local password file (unencrypted)"
	if (Test-Path '.\password.txt') {
		Write-Verbose "  Local password file found. Pulling username"
		try {
			$IDRACPASSWORD = Get-Content '.\password.txt'
			Write-Verbose "      Password: (found)"
		} catch {
			Write-Verbose "    Error pulling password"
			Write-Verbose "    $($_.Exception.Message)"
			$IDRACPASSWORD = ''
		}
	}
}

function Get-IPMI {
	param (
		[string[]] $text = ''
	)
	write-Verbose "  Running IPMITool with $($text)"
	try {
		& "$PathToIPMItool\ipmitool.exe" -I lanplus -U $script:IDRACUSER -P $script:IDRACPASSWORD -H $IDRACIP $text 2> $null
	} catch {
		Write-Verbose "  Error running IPMITool"
		Write-Verbose "  $($_.Exception.Message)"
	}
}

if (($IDRACUSER) -and ($IDRACPASSWORD)) {
	Write-Verbose "Polling temperature"
	$ipmiTemp = Get-IPMI -text 'sdr type temperature'.split(' ')
	$PlanarTemp = [int] ((($ipmiTemp | Select-String 'io1 planar').tostring().split('|'))[-1].Trim() -split ' ')[0]
	$AmbientTemp = [int] ((($ipmiTemp | Select-String 'ambient temp').tostring().split('|'))[-1].Trim() -split ' ')[0]
	$PlanarTempF = ((1.8 * $PlanarTemp) + 32 )
	$AmbientTempF = ((1.8 * $AmbientTemp) + 32 )
	$Message += "Planar temperature is: $($PlanarTemp.ToString())C / $($PlanarTempF.ToString())F`r`n"
	$Message += "Ambient temperature is: $($AmbientTemp.ToString())C / $($AmbientTempF.ToString())F`r`n"
	Write-Verbose "    Planar temperature is: $($PlanarTemp.ToString())C / $($PlanarTempF.ToString())F"
	Write-Verbose "    Ambient temperature is: $($AmbientTemp.ToString())C / $($AmbientTempF.ToString())F"

	if ($PlanarTemp -gt 61) {
		Write-Verbose "Enabling Dynamic Fan Control"
		$Message += "  Enabling Dynamic Fan Control`r`n`r`n"
		Get-IPMI -text 'raw 0x30 0x30 0x01 0x01'.Split(' ')
		$FanSpeed = 9999
	} elseif ($PlanarTemp -gt 51) {
		Write-Verbose "Setting Fans to 4.2k"
		$Message += "  Setting Fans to 4.2k`r`n`r`n"
		$null = get-ipmi -text 'raw 0x30 0x30 0x01 0x00'.Split(' ')
		$null = get-ipmi -text 'raw 0x30 0x30 0x02 0xff 0x1a'.Split(' ')
		$FanSpeed = 4200
	} else {
		Write-Verbose "Setting Fans to 2.2k"
		$Message += "  Setting Fans to 2.2k`r`n`r`n"
		$null = Get-IPMI -text 'raw 0x30 0x30 0x01 0x00'.Split(' ')
		$null = Get-IPMI -text 'raw 0x30 0x30 0x02 0xff 0x09'.Split(' ')
		$FanSpeed = 2200
	}

	Write-Verbose "Checking current fan speeds"
	$ipmiFan = Get-IPMI -text 'sdr type Fan'.split(' ') | Where-Object { $_ -match 'RPM' }
	$meas = $ipmiFan | ForEach-Object {
		($_ -split "\|")[-1].Trim("RPM").Trim()
	} | Measure-Object -average
	write-verbose "    Fans: $($meas.Count)"
	write-verbose "    RPM : $($meas.Average)"
	if ($LogFile) {
		Write-Verbose "Writing to logfile: $LogFile"
		[string] $LogText = "$((Get-Date).ToString())`t$PlanarTempF`t$AmbientTempF`t$($meas.Count)`t$($meas.Average)"
		$LogText | Out-File -FilePath $LogFile -Append -ErrorAction SilentlyContinue
	}
} else {
	Write-Verbose "  Username/Password not found."
	$Message += "  Username/Password not found.`r`n"
}

Write-Verbose "Writing to Application Eventlog"
$Message += 'Fan Speed Script End: '
$Message += $(Get-Date).ToString()
$Message += "`r`n`r`n"
Write-EventLog -LogName "Application" -Source 'FanSpeed' -eventid 9999 -EntryType Information -Message $Message -ErrorAction SilentlyContinue
