param(
	[Parameter(Mandatory=$true)]
    [string]$primaryVMName,

	[Parameter(Mandatory=$true)]
    [string]$sqlUser,

	[Parameter(Mandatory=$true)]
    [string]$sqlPass
)

$logFile = "c:\$(get-date -f yyyy-MM-dd_HHmmss)-check-suspendedDBs_log.txt"
New-Item -Path "c:\" -Name "$(get-date -f yyyy-MM-dd_HHmmss)-check-suspendedDBs_log.txt" -ItemType "file" -Force

function writeToLogFile([string]$message) {
	Add-Content -Path $logFile -Value $message
}
	
function checkThatNoDBIsInSuspendedModeinPrimaryServerInAG([string]$primaryVMName, [string]$sqlUser, [string]$sqlPass) {

	$primaryServerConnectionString = "Server=$primaryVMName;Database=master;User Id=$sqlUser;Password=$sqlPass;TrustServerCertificate=True"
	
	Write-Output "Primary SQL server name: $primaryVMName"
	writeToLogFile "Primary SQL server name: $primaryVMName"

	# writeToLogFile "ConnString: $primaryServerConnectionString"
	
	Write-Output "Checking that there are no DBs in suspended mode in the AG..."
	writeToLogFile "Checking that there are no DBs in suspended mode in the AG..."
	
	$query = 'SELECT count(*) as [suspendedDBcount] FROM master.sys.availability_groups AS AG LEFT OUTER JOIN master.sys.dm_hadr_availability_group_states as agstates ON AG.group_id = agstates.group_id INNER JOIN master.sys.availability_replicas AS AR ON AG.group_id = AR.group_id INNER JOIN master.sys.dm_hadr_availability_replica_states AS arstates ON AR.replica_id = arstates.replica_id AND arstates.is_local = 1 INNER JOIN master.sys.dm_hadr_database_replica_cluster_states AS dbcs ON arstates.replica_id = dbcs.replica_id LEFT OUTER JOIN master.sys.dm_hadr_database_replica_states AS dbrs ON dbcs.replica_id = dbrs.replica_id AND dbcs.group_database_id = dbrs.group_database_id where dbrs.is_suspended = 1;'
	
	# writeToLogFile $query
		
	$result = (Invoke-Sqlcmd -ConnectionString $primaryServerConnectionString $query)

	Write-Output $result.suspendedDBcount
	writeToLogFile $result.suspendedDBcount

	if ($result.suspendedDBcount -gt 0) {
		$errorMessage = "Error! There are DBs in AG that are in suspended mode."
		Write-Output $errorMessage
		writeToLogFile $errorMessage
		throw $errorMessage
	}
		
	Write-Output "Check ok."
	writeToLogFile "Check ok."
}

checkThatNoDBIsInSuspendedModeinPrimaryServerInAG $primaryVMName $sqlUser $sqlPass
