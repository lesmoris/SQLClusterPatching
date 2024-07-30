param(
	[Parameter(Mandatory=$true)]
    [string]$VMName,

	[Parameter(Mandatory=$true)]
    [string]$sqlUser,

	[Parameter(Mandatory=$true)]
    [string]$sqlPass
)

$logFile = "c:\$(get-date -f yyyy-MM-dd_HHmmss)-check-primaryServerInAG.txt"
New-Item -Path "c:\" -Name "$(get-date -f yyyy-MM-dd_HHmmss)-check-primaryServerInAG.txt" -ItemType "file" -Force

function writeToLogFile([string]$message) {
	Add-Content -Path $logFile -Value $message
}
	
function checkIfVMIsPrimaryReplicaInAG([string]$VMName, [string]$sqlUser, [string]$sqlPass) {

	$serverConnectionString = "Server=$VMName;Database=master;User Id=$sqlUser;Password=$sqlPass;TrustServerCertificate=True"
	
	Write-Output "SQL Server name: $VMName"
	writeToLogFile "SQL server name: $VMName"

	# writeToLogFile "ConnString: $serverConnectionString"
	
	Write-Output "Checking if it is the primary replica in the AG..."
	writeToLogFile "Checking if it is the primary replica in the AG..."
	
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

checkIfVMIsPrimaryReplicaInAG $VMName $sqlUser $sqlPass
