param(
	[Parameter(Mandatory=$true)]
    [string]$message
)

$logFile = "c:\$(get-date -f yyyy-MM-dd_HHmmss)-sendEmail.txt"
New-Item -Path "c:\" -Name "$(get-date -f yyyy-MM-dd_HHmmss)-sendEmail.txt" -ItemType "file" -Force

function writeToLogFile([string]$message) {
	Add-Content -Path $logFile -Value $message
}

function sendEmail([string]$message) {

	$message = $message -replace ",", "`n"

    $HTML = "<HTML><BODY>" + $message + "</BODY></HTML>"

	writeToLogFile $HTML

    Try{
        Write-Output "Sending email..."

        Send-MailMessage -to "" -from "" -Subject "SQL Server Patching Report" -SmtpServer "" -Body $html -BodyAsHtml -Verbose -ErrorAction "Stop"
    }
    catch { 
        $message = "$($_.Exception.Message)"
        Write-Output "Exception Message: $message"
		writeToLogFile "Exception Message: $message"
        throw $_.Exception
    }
    finally { 
        if ($null -eq $message){
            Write-Output "Email sent."
			writeToLogFile "Exception Message: $message"
        }
    }
}

sendEmail $message