## FILENAME: AppMon.ps1
############################################################################
## Script Name: [Application Monitor]
## Created: [05/05/2011]
## Author: Mick Shaw
## 
##
############################################################################
## PURPUSE: 
##          1) Monitors AVAYA IVR Webserver Application logs for DB socket write errors
##          2) If error occurs restart the tomcat service
##          3) Notify receipents of the event
##
############################################################################
##
## REVISION HISTORY
## 05/10/2011
##
## ISSUE: StreamReader cannot open log file because it is being used by the tomcat process
##
## RESOLUTION: Utilize filestream overload in the CheckLog function.
##
##
############################################################################
##FUNCTION LISTINGS
###################
## Function: MailSend 
## Created: [05/04/2011]
## Purpose: Provide notification after tomcat service has been restarted
##
## Powershell version 2.0 (Send-MailMessage cmdlet)
##
## 
############################################################################ 

function MailSend {
param( 

$logentries,
## The recipient of the mail message 
$notificationfrom = "some_recipient@email.com",

## The subject of the message 
$subject = "DB Socket Error VXML Server: $env:COMPUTERNAME", 

## The body of the message 
$body = "All Concerned,`n`n An Application error has been logged in the last 30 minutes. `n`nApp Server $env:COMPUTERNAME was unable to write to the external Database.  Socket errors have been logged. An attempt to re-establish the connection has been made by restarting the AppServer service.  Please verify all services.`n",

## The SMTP host that will transmit the message 
$smtpserver = "some_smtpservice.smtp.com", 

## The sender of the message 
$notificationto = "recipient@email.com" 
#$notificationto = "mshaw@potomacintegration.com" 
	)

## Send the mail 
Send-MailMessage -To $notificationto `
-From $notificationfrom `
-Subject "$subject" `
-Body "$body" `
-SmtpServer $smtpserver `
}
############################################################################
# Function: CheckLog
# Created: [05/05/2011]
# Version: 2.0
#
# Arguments: signatures.txt
#
############################################################################
# Purpose: Will search every line of a textual log file against every regex
#          pattern provided in a second file, producing a summary of matches
#          found, or, if -ShowMatchedLine switch is specified, only the log lines
#          which matched at least one regex with no summary report.
#
#
############################################################################
function CheckLog {

param ($logfile, $patternsfile, [Switch] $ShowMatchedLines)

# Load file with the regex patterns, but ignore blank lines.  
$patterns = ( get-content $patternsfile | where-object {$_.length -ne 0} ) 


# From each line in $patterns, extract the regex pattern and its description, add these 
# back as synthetic properties to each line, plus a counter of matches initialized to zero.

foreach ($line in $patterns) 
{
    if ( $line -match "(?<pattern>^[^\t]+)\t+(?<description>.+$)" )
    { 
        add-member -membertype NoteProperty -name Pattern     -value $matches.pattern     -input $line | out-null
        add-member -membertype NoteProperty -name Description -value $matches.description -input $line | out-null
        add-member -membertype NoteProperty -name Count       -value 0                    -input $line | out-null
    }
}

# Remove lines which could not be parsed correctly (they will not have Count property).
# If you have comments lines, don't include any tabs in those lines so they'll be ignored.
$patterns = ( $patterns | where-object {$_.count -ne $null } ) 

# Use StreamReader to process each line of logfile, one line at a time, comparing each line against
# all the patterns, incrementing the counter of matches to each pattern.  Have to use StreamReader
# because get-content and the Switch statement are extremely slow with large files.  

$LogIO = New-Object system.IO.filestream  -ArgumentList "$logfile", ([io.filemode]::Open), ([io.fileaccess]::Read), ([io.fileshare]::ReadWrite)
$reader = New-Object System.IO.StreamReader($LogIO)

if (-not $?) { "`nERROR: Could not find file: $logfile`n" ; exit }


while (!$reader.EndOfStream)
{
    while ( ([String] $line = $reader.readline()) -ne $null) 
    {
        #Ignore blank lines and comment lines.
        if ($line.length -eq 0 -or $line.startswith(";") -or $line.startswith("#") ) { continue }

            foreach ($pattern in $patterns) 
            {
                if ($line -match $pattern.pattern) 
                    {
                        if ($ShowMatchedLines) { $line ; break }  #Break out of foreach, one match good enough.
                        $pattern.count++ 
                    } 
            }
    }

}

# Emit count of patterns which matched at least one line.

if (-not $ShowMatchedLines) 
{
    $patterns | where-object { $_.count -gt 0 } | 
    select-object Count,Description,Pattern | sort-object count -desc
}

}
############################################################################
## Function: Console 
## Created: [05/07/2011]
## Purpose: Provides Console output to test changes to the script
##
## Powershell version 2.0 (Send-MailMessage cmdlet)
##
## 
############################################################################ 
function Console {

Write-Host Current time is: $TranslateNow
 Write-Host Time 30 minutes ago is $NowMinus30Minutes
 Write-Host --------All Errors Today--------------
 
 $ArgErrorTimestrans
 
 Write-Host --Errors in the last 30 minutes-------
 
 $ArgErrorsinlast30minutes
 
 $strErrorLog
 }
 
 
############################################################################
##
## SCRIPT BODY
##
############################################################################

## Initialize variables and Arrays
$strErrorLog = 0
$ArgErrorLog = @() 
$ArgTimestamps = @()
$ArgErrorTimes = @()
$ArgErrorTimestrans = @()
$ArgErrorsinlast30minutes = @()

## Time Minupulations
$Format = "HH:mm"
$Now = Get-Date -uformat "%H:%M"
$TranslateNow = [DateTime]::ParseExact($Now, $Format, $provider)
$NowMinus30Minutes = [DateTime]::Now.Subtract([TimeSpan]::FromMinutes(30))

## Filter Logfile against all lines that start with "ERROR" and include "write socket "error"
$strErrorLog = CheckLog -logfile D:\AVAYA\DCGOV\tomcat6_0_24\logs\DCGovt_DB.log -patterns D:\ApplicationMonitor\signatures.txt -ShowMatchedLines


#Split lines into an array of 6 indexes (EventType, Day, Month, Year, Time, EventMessage) 

if ($strErrorLog -ne $null)
    {
        $ArgErrorLog = $strErrorLog |% {$_.split(" ",6)
    }
  
            for ($i=4; $i -lt $ArgErrorLog.length; $i+=12)
            {

                $ArgTimestamps += $ArgErrorLog[$i] 

            }

            foreach ($Timestamp in $ArgTimestamps)
            {
    
                $ArgErrorTimes += $Timestamp.Substring(0,5) 
     
            }
            
            foreach ($ErrorTime in $ArgErrorTimes)
            {
    
                $ArgErrorTimestrans += [DateTime]::ParseExact($ErrorTime, $Format, $provider) 
            
            } 
     
            foreach ($ErrorTimetran in $ArgErrorTimestrans)
            {
            
                if (($ErrorTimetran -lt $TranslateNow) -and ($ErrorTimetran -ge $NowMinus30Minutes))
                {
    
                    $ArgErrorsinlast30minutes += $ErrorTimetran
    
                 }     
             } 

            If ( $ArgErrorsinlast30minutes)
            
            {
                
                MailSend;
                Restart-Service DCGOVAvayaAppServer;
                 exit
            }
 
            else{
                
                  exit
    
                }
    }
    
    else{
    
        exit
        
        }                
 

 #Console #Uncomment Console and modify console function for testing output
 
        
############################################################################
##
## END OF SCRIPT: [Application Monitor]
##
############################################################################
