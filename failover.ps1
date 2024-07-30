param(
	[Parameter(Mandatory=$true)]
    [string]$primaryVMName,

	[Parameter(Mandatory=$true)]
    [string]$secondaryVMName,
	
	[Parameter(Mandatory=$true)]
    [string]$resourceGroupName,

	[Parameter(Mandatory=$true)]
    [string]$availabilityGroupName,

	[Parameter(Mandatory=$true)]
    [string]$sqlUser,

	[Parameter(Mandatory=$true)]
    [string]$sqlPass
)

$logFile = "c:\$(get-date -f yyyy-MM-dd_HHmmss)-action-failover_log.txt"
New-Item -Path "c:\" -Name "$(get-date -f yyyy-MM-dd_HHmmss)-action-failover_log.txt" -ItemType "file" -Force

function writeToLogFile([string]$message) {
	Add-Content -Path $logFile -Value $message
}

function checkIfVMIsPrimaryReplicaInAG([string]$VMName, [string]$sqlUser, [string]$sqlPass) {

	$serverConnectionString = "Server=$VMName;Database=master;User Id=$sqlUser;Password=$sqlPass;TrustServerCertificate=True"

	# writeToLogFile "ConnString: $serverConnectionString"
	
	Write-Output "Checking if $VMName is the primary replica in the AG..."
	writeToLogFile "Checking if $VMName is the primary replica in the AG..."
	
	$query = "SELECT 1 as [isPrimary] FROM master.sys.availability_groups Groups INNER JOIN master.sys.availability_replicas Replicas ON Groups.group_id = Replicas.group_id INNER JOIN master.sys.dm_hadr_availability_group_states States ON Groups.group_id = States.group_id where replica_server_name = '" + $VMName + "' and (primary_replica  = replica_server_name)"
	
	# writeToLogFile $query
		
	$result = (Invoke-Sqlcmd -ConnectionString $serverConnectionString $query)

	Write-Output $result.isPrimary
	writeToLogFile $result.isPrimary

	if ($result.isPrimary -ne 1) {
		$errorMessage = "Error! $VMName is not primary replica in AG"
		Write-Output $errorMessage
		writeToLogFile $errorMessage
		throw $errorMessage
	}
		
	Write-Output "Check ok."
	writeToLogFile "Check ok."
}
	
function performFailover([string]$primaryVMName, [string]$secondaryVMName, [string]$availabilityGroupName, [string]$sqlUser, [string]$sqlPass) {

	$primaryServerConnectionString = "Server=$primaryVMName;Database=master;User Id=$sqlUser;Password=$sqlPass;TrustServerCertificate=True"
	$secondaryServerConnectionString = "Server=$secondaryVMName;Database=master;User Id=$sqlUser;Password=$sqlPass;TrustServerCertificate=True"
	
	Write-Output "Primary SQL server name: $primaryVMName"
	Write-Output "Secondary SQL server name: $secondaryVMName"
	writeToLogFile "Primary SQL server name: $primaryVMName"
	writeToLogFile "Secondary SQL server name: $secondaryVMName"
	
	$timeout = [System.Diagnostics.Stopwatch]::StartNew()
	$maxTimeoutSeconds = 180 # 3 minutes

	# Test that DBs are being ok before failover in secondary server. If any Warning => wait for 30 more secs and retest. 
	Write-Output "Checking that the failover can be performed OK..."
	writeToLogFile "Checking that the failover can be performed OK..."
	do {
		
		$query = "SELECT (Select count(*) FROM sys.databases where state_desc in ('RECOVERING', 'RECOVERY_PENDING') ) as 'recovering', (SELECT count(*) FROM sys.databases where state_desc not in ('ONLINE', 'RECOVERING', 'RECOVERY_PENDING')) as 'errors' "
		
		$primaryServerstatus = (Invoke-Sqlcmd -ConnectionString $primaryServerConnectionString $query)
		$secondaryServerstatus = (Invoke-Sqlcmd -ConnectionString $secondaryServerConnectionString $query)
		
		# If still some DBs are in RECOVERY status => Wait for DBs to finish synchronising
		if ($primaryServerstatus.recovering -ne 0 -or $secondaryServerstatus.recovering -ne 0) { 
			Write-Output  "Some DBs still synchronising. Let's wait a little bit..." 
			writeToLogFile "Some DBs still synchronising. Let's wait a little bit..." 
		}

		# If any Error => Abort and send a message
		if ($primaryServerstatus.errors -ne 0) {
			writeToLogFile "Errors in server $primaryVMName before FailOver. Please check." 
			throw "Errors in DB replica in server $primaryVMName before FailOver. Please check." 
		}
		
		if ($secondaryServerstatus.errors -ne 0) { 
			writeToLogFile "Errors in server $secondaryVMName before FailOver. Please check." 
			throw "Errors in DB replica in server $secondaryVMName before FailOver. Please check." 
		}
		
		Start-Sleep -Seconds 30
		
	} while (($primaryServerstatus.recovering -ne 0 -or $secondaryServerstatus.recovering -ne 0) -and $timeout.Elapsed.TotalSeconds -lt $maxTimeoutSeconds) 
	
	if ($primaryServerstatus.recovering -ne 0 -or $secondaryServerstatus.recovering -ne 0) { 
		writeToLogFile "Some DBs still synchronising within the allotted time. Please check $primaryVMName and $secondaryVMName." 
		throw "Some DBs still synchronising within the allotted time. Please check $primaryVMName and $secondaryVMName." 
	}

	Write-Output "Ready to perform the failover"
	writeToLogFile "Ready to perform the failover"

	try {
		Write-Output "Switching AG from $primaryVMName to $secondaryVMName..."
		writeToLogFile "Switching AG from $primaryVMName to $secondaryVMName..."

		$sqlCmd = "ALTER AVAILABILITY GROUP [$availabilityGroupName] FAILOVER"

		Invoke-Sqlcmd -ConnectionString $secondaryServerConnectionString $sqlCmd
	}
	catch {
		$message = $_
		writeToLogFile "Error switching AG: $message"
		exit
	}

	checkIfVMIsPrimaryReplicaInAG $secondaryVMName $sqlUser $sqlPass		

	Write-Output "Switch done."
	writeToLogFile "Switch done."
	
	$timeout = [System.Diagnostics.Stopwatch]::StartNew()
	$maxTimeoutSeconds = 180 # 3 minutes

	# Wait for 30 secs and then test that DBs are being sunchronized after failover. If any Warning => wait for 30 more secs and retest. 
	Write-Output "Checking that the failover finished OK..."
	writeToLogFile "Checking that the failover finished OK..."
	do {
		Start-Sleep -Seconds 30
		
		$query = "SELECT (Select count(*) FROM sys.databases where state_desc in ('RECOVERING', 'RECOVERY_PENDING') ) as 'recovering', (SELECT count(*) FROM sys.databases where state_desc not in ('ONLINE', 'RECOVERING', 'RECOVERY_PENDING')) as 'errors' "
		
		$primaryServerstatus = (Invoke-Sqlcmd -ConnectionString $primaryServerConnectionString $query)
		$secondaryServerstatus = (Invoke-Sqlcmd -ConnectionString $secondaryServerConnectionString $query)
		
		# If still some DBs are in RECOVERY status => Wait for DBs to finish synchronising
		if ($primaryServerstatus.recovering -ne 0 -or $secondaryServerstatus.recovering -ne 0) { 
			Write-Output  "Some DBs still synchronising. Let's wait a little bit..." 
			writeToLogFile "Some DBs still synchronising. Let's wait a little bit..." 
		}

		# If any Error => Abort and send a message
		if ($primaryServerstatus.errors -ne 0) {
			writeToLogFile "Errors in server $primaryVMName after FailOver. Please check." 
			throw "Errors in DB replica in server $primaryVMName after FailOver. Please check." 
		}
		
		if ($secondaryServerstatus.errors -ne 0) { 
			writeToLogFile "Errors in server $secondaryVMName after FailOver. Please check." 
			throw "Errors in DB replica in server $secondaryVMName after FailOver. Please check." 
		}
		
	} while (($primaryServerstatus.recovering -ne 0 -or $secondaryServerstatus.recovering -ne 0) -and $timeout.Elapsed.TotalSeconds -lt $maxTimeoutSeconds) 
	
	if ($primaryServerstatus.recovering -ne 0 -or $secondaryServerstatus.recovering -ne 0) { 
		writeToLogFile "Some DBs still synchronising within the allotted time. Please check $primaryVMName and $secondaryVMName." 
		throw "Some DBs still synchronising within the allotted time. Please check $primaryVMName and $secondaryVMName." 
	}

	Write-Output  "Everything ok, moving on..."
	writeToLogFile  "Everything ok, moving on..."
}

performFailover $primaryVMName $secondaryVMName $availabilityGroupName $sqlUser $sqlPass
