<h1>SQL Server Cluster Patching</h1>

<h2>Description</h2>
These scripts aim to patch a SQL Cluster inside two Azure VMs. The process is the following:

Patch secondary server inside the cluster.
Restart secondary server inside the cluster.
Perform failover from primary to secondary
Patch primary server inside the cluster.
Restart primary server inside the cluster.
Perform failover from secondary to primary.

It performs the necesary validations before and after doing each step. 

The main script is runbook.ps1. Set these variables before running that script:

$primaryVMName = "" 
$secondaryVMName = "" 
$resourceGroupName = ""
$availabilityGroupName = ""	
$keyVault = ""

<h2>Pre-Requisites</h2>
SQL Account with permissions to be able to perform a failover between the two nodes of the SQL Cluster. They must be stored inside an Azure KeyVault.
The  Automation Account must have reading permissions over the secrets in that  an Azure KeyVault
The Automation Account must be Contributor over the two VMs.