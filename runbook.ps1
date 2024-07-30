function sendEmail([string]$message) {

    $ScriptToRun = Invoke-RestMethod -Uri "https://<storageaccount>.blob.core.windows.net/runbookscript/sendEmail.ps1"
	Out-File -InputObject $ScriptToRun -FilePath sendEmail.ps1

	# Write-Output $ScriptToRun

    $message = $message -replace "`n", ","

	$params=@{
	 "message" = $message;
	}

	$results = Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $emailServerVMName -CommandId 'RunPowerShellScript' -ScriptPath sendEmail.ps1 -Parameter $params -ErrorVariable errortext 

	if ($null -eq $results) {
		$errorMessage = "Function sendEmail : Error running Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $primaryVMName -CommandId 'RunPowerShellScript' -ScriptPath sendEmail.ps1 -Parameter $params `n $errortext"
		throw $errorMessage
	}

	if ($results.Status -ne "Succeeded") {
		$errorMessage = "Function sendEmail : Error sending email. Output: `n" + $results.Value[0].Message
		throw $errorMessage
	}

	if ($results.Value.Message -like "*error*") {
		$errorMessage = "Function sendEmail : Error sending email. Output: `n" + $results.Value.Message
		throw $errorMessage
	}	
	
	Write-Output "Mail sent."
}

function patchVMandReboot([string]$VMName, [string]$resourceGroupName) {
	
	Write-Output  "Patching $VMName..."
	$global:globalStatusMessage += "Patching $VMName...`n"

	$patchVMscript = "Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -Verbose | Out-File 'C:\$(get-date -f yyyy-MM-dd_HHmmss)-WindowsUpdate.log' -force"
	# $patchVMscript = "Get-WindowsUpdate -Verbose | Out-File 'C:\$(get-date -f yyyy-MM-dd_HHmmss)-WindowsUpdate.log' -force"

	$results = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -CommandId 'RunPowerShellScript' -VMName $VMName -ScriptString $patchVMscript -ErrorVariable errortext 
	
	if ($null -eq $results) {
		$errorMessage = "Function patchVMandReboot : Error running Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -CommandId 'RunPowerShellScript' -VMName $VMName -ScriptString $patchVMscript `n $errortext"
		throw $errorMessage
	}

	if ($results.Status -ne "Succeeded") {
		$errorMessage = "Function patchVMandReboot : Error when patching $VMName. Output: `n" + $results.Value[0].Message
		throw $errorMessage
	}

	if ($results.Value.Message -like "*error*") {
		$errorMessage = "Function patchVMandReboot : Error when patching $VMName. Output: `n" + $results.Value.Message
		throw $errorMessage
	}	
	
	Write-Output  "$VMName patched. Output:"
	Write-Output  $results.Value[0].Message
	$global:globalStatusMessage += "$VMName patched. Output:`n"
		
	Write-Output  "Restarting $VMName..."
	$global:globalStatusMessage += "Restarting $VMName...`n"
	
	$results = Restart-AzVM -ResourceGroupName $resourceGroupName -Name $VMName
	
	if ($results.Status -ne "Succeeded") {
		throw "Error restarting patching $VMName. Please check"
	}	
	
	# Wait until the Vm start the service and joins the SQL cluster
	Start-Sleep -Seconds 30

	Write-Output "$VMName is up and running again. A log of the updates can be found inside the VM, in C:\. Moving on..."
	$global:globalStatusMessage += "$VMName is up and running again. A log of the updates can be found inside the VM, in C:\. Moving on...`n"
}

function performFailover([string]$primaryVMName, [string]$secondaryVMName, [string]$resourceGroupName, [string]$availabilityGroupName, [System.Object[]]$credentials) {
	
	try {
		$ScriptToRun = Invoke-RestMethod -Uri "https://<storageaccount>.blob.core.windows.net/runbookscript/failover.ps1"
		Out-File -InputObject $ScriptToRun -FilePath failover.ps1
	}
	catch {
		throw "Function performFailover : Error downloading script from storageaccount. Output: `n" + $_.Exception.Message
	}

	# Write-Output $ScriptToRun

	$params=@{
	 "primaryVMName" = $primaryVMName;
	 "secondaryVMName" = $secondaryVMName;
	 "resourceGroupName" = $resourceGroupName;
	 "availabilityGroupName" = $availabilityGroupName;
	 "sqlUser" = $credentials.sqlUser;
	 "sqlPass" = $credentials.sqlPass; 
	}

	Write-Output "Performing SQL Failover on AG $availabilityGroupName from $primaryVMName to $secondaryVMName..."
	$global:globalStatusMessage += "Performing SQL Failover on AG $availabilityGroupName from $primaryVMName to $secondaryVMName...`n"

	$results = Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $primaryVMName -CommandId 'RunPowerShellScript' -ScriptPath failover.ps1 -Parameter $params -ErrorVariable errortext 
	
	if ($null -eq $results) {
		$errorMessage = "Function performFailover : Error running Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $primaryVMName -CommandId 'RunPowerShellScript' -ScriptPath failover.ps1 -Parameter $params `n $errortext"
		throw $errorMessage
	}

	if ($results.Status -ne "Succeeded") {
		$errorMessage = "Function performFailover : Error running the script. Output: `n" + $results.Value[0].Message
		throw $errorMessage
	}

    if ($results.Value.Message -like '*error*') {
   		$errorMessage = "Function performFailover : Error doing SQL failover. Output: `n" + $results.Value.Message
		throw $errorMessage
    }
	
	Write-Output "Failover done. Check C:\failover_log.txt inside $primaryVMName for more info. Moving on..."	
	$global:globalStatusMessage += "Failover done. Check C:\failover_log.txt inside $primaryVMName for more info. Moving on...`n"
}

function checkThatVMisPrimaryServerInAG([string]$VMName, [string]$resourceGroupName, [System.Object[]]$credentials) {

    Write-Output "Checking if $VMName is the primary replica in the AG..."
	$global:globalStatusMessage += "Checking if $VMName is the primary replica in the AG...`n"

    $ScriptToRun = Invoke-RestMethod -Uri "https://<storageaccount>.blob.core.windows.net/runbookscript/primaryServerInAG.ps1"
	Out-File -InputObject $ScriptToRun -FilePath primaryServerInAG.ps1

	# Write-Output $ScriptToRun

	$params=@{
	 "VMName" = $VMName;
	 "sqlUser" = $credentials.sqlUser;
	 "sqlPass" = $credentials.sqlPass; 
	}

	$results = Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath primaryServerInAG.ps1 -Parameter $params -ErrorVariable errortext 
	# Write-Output $results.Value

	if ($null -eq $results) {
		$errorMessage = "Function checkThatVMisPrimaryServerInAG : Error running Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath primaryServerInAG.ps1 -Parameter $params `n $errortext"
		throw $errorMessage
	}

	if ($results.Status -ne "Succeeded" ) {
		$errorMessage = "Function checkThatVMisPrimaryServerInAG : Error running the script. Output: `n" + $results.Value[0].Message
		throw $errorMessage
	}

    if ($results.Value.Message -like '*error*') {
   		$errorMessage = "Function checkThatVMisPrimaryServerInAG : Error checking if VM is Primary Server in AG. Output: `n" + $results.Value.Message
		throw $errorMessage
    }

   	Write-Output "Check done."
	$global:globalStatusMessage += "Check done.`n"

}

function checkThatNoDBIsInSuspendedModeinPrimaryServerInAG([string]$primaryVMName, [string]$resourceGroupName, [System.Object[]]$credentials) {

    Write-Output "Checking that there are no DBs in suspended mode in the AG..."
	$global:globalStatusMessage += "Checking that there are no DBs in suspended mode in the AG...`n"

    $ScriptToRun = Invoke-RestMethod -Uri "https://<storageaccount>.blob.core.windows.net/runbookscript/supendedDBs.ps1"
	Out-File -InputObject $ScriptToRun -FilePath supendedDBs.ps1

	# Write-Output $ScriptToRun

	$params=@{
	 "primaryVMName" = $primaryVMName;
	 "sqlUser" = $credentials.sqlUser;
	 "sqlPass" = $credentials.sqlPass; 
	}

	$results = Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $primaryVMName -CommandId 'RunPowerShellScript' -ScriptPath supendedDBs.ps1 -Parameter $params -ErrorVariable errortext 
	
    # Write-Output $results.Value

	if ($null -eq $results) {
		$errorMessage = "Function checkThatNoDBIsInSuspendedModeinPrimaryServerInAG : Invoke-AzVMRunCommand -ResourceGroup $resourceGroupName -Name $primaryVMName -CommandId 'RunPowerShellScript' -ScriptPath supendedDBs.ps1 -Parameter $params `n $errortext"
		throw $errorMessage
	}

	if ( $results.Status -ne "Succeeded" ) {
		$errorMessage = "Function checkThatNoDBIsInSuspendedModeinPrimaryServerInAG : Error running the script. Output: `n" + $results.Value[0].Message
		throw $errorMessage
	}

    if ( $results.Value.Message -like '*error*') {
   		$errorMessage = "Function checkThatNoDBIsInSuspendedModeinPrimaryServerInAG : Error checking that there are not DBs in suspended mode. Output: `n" + $results.Value.Message
		throw $errorMessage
    }

   	Write-Output "Check done."
	$global:globalStatusMessage += "Check done.`n"
}

function getSQLCredentialsFromKV([string]$keyVault, [string]$resourceGroupName) {

    try {

        Write-Output "Getting SQL credentials from KeyVault..."
		$global:globalStatusMessage += "Getting SQL credentials from KeyVault...`n"

        $ip = (Invoke-WebRequest -uri "http://ifconfig.me/ip" -UseBasicParsing).Content

        Add-AzKeyVaultNetworkRule -VaultName $keyVault -IpAddressRange "$ip/32"

        $sqlUser = Get-AzKeyVaultSecret -VaultName $keyVault -Name EU-IPENDO-AUTOACCOUNT-PROD-sqluser -AsPlainText
        $sqlPass = Get-AzKeyVaultSecret -VaultName $keyVault -Name EU-IPENDO-AUTOACCOUNT-PROD-sqlpass -AsPlainText

        Write-Output "Done!"

        $credentials=@{
            "sqlUser" = $sqlUser;
            "sqlPass" = $sqlPass; 
        }

        return $credentials

    }
    finally {
	    Remove-AzKeyVaultNetworkRule -VaultName $keyVault -IpAddressRange "$ip/32"
    }
}

try {
	
	$primaryVMName = "" 
	$secondaryVMName = "" 
	$resourceGroupName = ""
	$availabilityGroupName = ""	
	$keyVault = ""
	$emailServerVMName = ""
	$global:globalStatusMessage = ""

    Write-Output "Logging in to Azure..."
	$global:globalStatusMessage +="Logging in to Azure...`n"

    Connect-AzAccount -Identity

    $credentials = getSQLCredentialsFromKV $keyVault

	# Check that both VMs and SQL Servers are in the correct state before doing anything
	checkThatVMisPrimaryServerInAG $primaryVMName $resourceGroupName $credentials
	checkThatNoDBIsInSuspendedModeinPrimaryServerInAG $primaryVMName $resourceGroupName $credentials

	# Install patches in Secondary (with reboot)
	patchVMandReboot $secondaryVMName $resourceGroupName

	# Failover to Secondary
	performFailover $primaryVMName $secondaryVMName $resourceGroupName $availabilityGroupName $credentials

	# Check that both VMs and SQL Servers are in the correct state before contuining with the next step
	checkThatVMisPrimaryServerInAG $secondaryVMName $resourceGroupName $credentials
	checkThatNoDBIsInSuspendedModeinPrimaryServerInAG $secondaryVMName $resourceGroupName $credentials

	# Install patches in Primary (with reboot)
	patchVMandReboot $primaryVMName $resourceGroupName
	
	# Failover back to Primary
	performFailover $secondaryVMName $primaryVMName $resourceGroupName $availabilityGroupName $credentials

	# Check that VMs and SQL Servers are in the correct state before finishing
	checkThatVMisPrimaryServerInAG $primaryVMName $resourceGroupName $credentials
	checkThatNoDBIsInSuspendedModeinPrimaryServerInAG $primaryVMName $resourceGroupName $credentials

	# Everything good! Send email with status
	$global:globalStatusMessage += "All done!`n"
    sendEmail $global:globalStatusMessage

}
catch {
	$global:globalStatusMessage += "Error: $_.Exception.Message`n"
	sendEmail $global:globalStatusMessage
    throw $_.Exception
}