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