<# 
 .Synopsis
  Executes an external process.

 .Description
  This function executes an external process and is used to invoke bcp & psql command
  used by other functions in the module. The function returns, standard error, standard
  output and the process exitcode.

 .Parameter filepath
  The full path including the process name to be executed.

 .Parameter arguments
  The arguments to be passed to the process

 .Example
  #Execute psql to return all rows from categories table
  Execute-Process -filepath "C:\Program Files\PostgreSQL\9.6\bin\psql.exe" -arguments "-h localhost -U postgres -d mydb -c (`"Select * from categories`")"
   
#>
function Execute-Process{
param(
[Parameter(Mandatory=$true)]
[string]$filepath,
[Parameter(Mandatory=$true)]
[string]$arguments
)

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $filepath
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false
$pinfo.Arguments = $arguments
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $pinfo
$p.Start() | Out-Null
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()
Write-Host "stdout: $stdout" -ForegroundColor Green
Write-Host "stderr: $stderr" -ForegroundColor Red
Write-Host "exit code: " + $p.ExitCode -ForegroundColor Yellow
}

<# 
 .Synopsis
  Executes a query on postgreSQL and retursn the result.

 .Description
  This function uses a postgreSQL ODBC driver to execute a query on specified postgreSQL server and 
  return the result in dataset table format. 

 .Parameter query
  The query to be executed on the postgreSQL server.

 .Parameter server
  The postgreSQL hostname 

  .Parameter db
  The database name in which the query is to be executed.
  
  .Parameter puser
  The postgreSQL user name under which the query is to be executed

 .Parameter ppwd
  The password for the username specified in puser parameter

 .Example
  $result = ExecuteQuery-PostgreSQL -server $server -db $database -puser postgres -ppwd postgres -query $query
  #do something with $results.
     
#>
function ExecuteQuery-PostgreSQL{
   param(
		[Parameter(Mandatory=$true)]
   [string]$query,
		[Parameter(Mandatory=$true)]
   [string]$server,
	   [Parameter(Mandatory=$true)]
   [string]$database,
	   [Parameter(Mandatory=$true)]
   [string]$puser,
	   [Parameter(Mandatory=$true)]
   [string]$ppwd
   )
   $conn = New-Object System.Data.Odbc.OdbcConnection
   $conn.ConnectionString = "Driver={PostgreSQL ODBC Driver(UNICODE)};Server=$server;Database=$database;Uid=$puser;Pwd=$ppwd;"
   $conn.open()
   $cmd = New-object System.Data.Odbc.OdbcCommand($query,$conn)
   $ds = New-Object system.Data.DataSet
   (New-Object system.Data.odbc.odbcDataAdapter($cmd)).fill($ds) | out-null
   $conn.close()
   $ds.Tables[0]
}


<# 
 .Synopsis
  Create SQL Server compatible scripts and tab delimited data for tables from a postgre database

 .Description
  This function generates out SQL Server compatible create tables script
  for all tables in the specified postgreSQL database. The function also genearates
  tab delimited files for the data in the tables.
  The function creates 1_Tables folder under the provided base path to script out table schema.

 .Parameter datapath
  The path where the table data is to be imported

 .Parameter server
  The postgreSQL hostname 

 .Parameter db
  The database name in which the query is to be executed.
 
 .Parameter puser
  The postgreSQL user name under which the query is to be executed

 .Parameter ppwd
  The password for the username specified in puser parameter

 .Parameter scriptpath
  The path to store the table creation scripts

 .Parameter psqlpath
  The psql utility location.

 .Parameter schema
  Specify the sql server schema you want to create the tables in. The default is dbo.

 .Parameter scriptoptions
  Specify "schema" to script out table creation scripts, "data" to export only table data
  and "all" to script out both creation script and data. The default is all.

 .Example
  #Script out table creation and data from postgreSQL to .sql files.
  Script-Table -datapath "C:\Projects\Migration\PostgrestoSQLServer\Data" -server="localhost" -db="mypostgredb" -puser="postgres" -scriptpath="C:\Projects\Migration\PostgrestoSQLServer\Schema" psqlpath = "C:\Program Files\PostgreSQL\9.6\bin\psql.exe" -scriptoptions="all"
     
#>
function Script-Table{
param
(
	[Parameter(Mandatory=$true)]
[string]$datapath,
[string]$server,
	[Parameter(Mandatory=$true)]
[string]$database,
	[Parameter(Mandatory=$true)]
[string]$puser,
[string]$ppwd,
	[Parameter(Mandatory=$true)]
[string]$scriptpath,
	[Parameter(Mandatory=$true)]
[string]$psqlpath,
[string]$schema="dbo",
[string]$scriptoptions="all" #schema/data/all
)
	#create destination directory if it doesn't exists
	if((Test-Path("$scriptpath\1_Tables")) -eq $false)
	{ 
		New-Item -Path "$scriptpath\1_Tables" -ItemType Directory | Out-Null
	}
	$scriptpath = "$scriptpath\1_Tables" 
	#get tables to export
	$query = "select table_schema || '.' || table_name As tablename from information_schema.tables where table_type = 'BASE TABLE' and table_schema != 'pg_catalog' AND table_schema != 'information_schema';"
	$result = ExecuteQuery-PostgreSQL -server $server -db $database -puser $puser -ppwd $ppwd -query $query
	$nl = [Environment]::NewLine;
	$tablename=""
	foreach($tbl in $result)
	{
		$tblfullname = $tbl.tablename;
		$tablename = $tbl.tablename.Split('.')[1];
		#script data
		if($scriptoptions -eq "All" -or $scriptoptions -eq "data")
		{
			$tsvpath = ($datapath + "\" + $tablename + ".csv").Replace("\","\\");
			$argument = "-h $server -U $puser -d $database -c `"COPY $tblfullname TO E'$tsvpath' WITH CSV"
			Execute-Process -filepath $psqlpath -arguments $argument
		}
		$colquery = "SELECT table_name,column_name,column_default,is_nullable,data_type,character_maximum_length,numeric_precision,udt_name from Information_Schema.Columns where table_name='$tablename';"
		$colresult = ExecuteQuery-PostgreSQL -server localhost -db $database -puser $puser -ppwd $ppwd -query $colquery
		$qry=""
		$dt = ""
		# script schema
		if($scriptoptions -eq "schema" -or $scriptoptions -eq "all")
		{
			# CHANGE THE DATA TYPES HERE.
			foreach($col in $colresult)
			{
				#parse datatype
				if($col.udt_name -eq "int8")
				{ 
					$dt = "bigint" 
				}
				elseif ($col.udt_name -eq "int4")
				{ 
					$dt= "int" 
				}
				elseif ($col.udt_name -eq "int2")
				{ 
					$dt= "smallint" 
				}
				elseif ($col.udt_name -eq "bytea")
				{ 
					$dt= "varbinary(max)" 
				}
				elseif ($col.udt_name -eq "timestamptz") 
				{ 
					$dt= "datetime2"
				}
				elseif ($col.udt_name -eq "timestamp")
				{
					$dt = "datetime"
				}
				elseif ($col.udt_name -eq "bool")
				{ 
					$dt= "varchar(5)"
				}
				elseif ($col.udt_name -eq "text")
				{ 
					$dt= "varchar(max)"
				}
				elseif ($col.udt_name -eq "bpchar")
				{ 
					$dt= "char"
				}
				elseif ($col.data_type -eq "USER-DEFINED" -or $col.udt_name -eq "tsvector" -or $col.udt_name -eq "_text")
				{
					$dt= "varchar(max)"
				}
				else
				{
					$dt=$col.udt_name;
				}
				#parse datatype length
				$cml = $col.character_maximum_length
				if([string]::IsNullOrEmpty($col.character_maximum_length))
				{ $dl = "" }
				else
				{ $dl = "(" + $col.character_maximum_length + ")" }
				#Add NULL/NOT NULL
				$nullable=""
				if($col.is_nullable -eq "NO")
				{ $nullable = " NOT NULL " }
				else
				{ $nullable = " NULL " }
				$qry= $qry + '"' +$col.column_name  + '" ' + $dt + $dl + $nullable + ",$nl" 
			}
			$qry = "Create Table `"$schema`".`"$tablename`"($nl $qry)"  
			$last_comma = $qry.LastIndexOf(',')
			$createtablequery = $qry.Remove($last_comma, 1).Insert($last_comma, '')
			Write-Host "Generating script for table $tablename..." -ForegroundColor Green
			$createtablequery | Out-File "$scriptpath\$tablename.sql"
		}
	}
}


<# 
 .Synopsis
  Script out primary key, foreign key, unique key, check constraint and sequences from postgreSQL in 
  SQL Server compatible .sql files

 .Description
  This function scripts out primary, foreign, unique keys, check constraint and sequences in SQL Server format.
  The function creates 2_Constraints folder for primary, foreign, unique & check constraints. 
  The function creates 3_Sequences folder for sequences.

 .Parameter server
  The postgreSQL hostname 

 .Parameter db
  The database name in which the query is to be executed.
  
 .Parameter puser
  The postgreSQL user name under which the query is to be executed

 .Parameter ppwd
  The password for the username specified in puser parameter

 .Parameter scriptpath
  The path to store the generated scripts

 .Parameter psqlpath
  The psql utility location.

 .Parameter schema
  Specify the sql server schema you want to create the tables in. The default is dbo.

 .Example
  #Script out above mentioned constraints from postgreSQL mypostgredb to specifed path
  Script-Constraints -server="localhost" -db="mypostgredb" -puser="postgres" -scriptpath="C:\Projects\Migration\PostgrestoSQLServer\Schema" psqlpath = "C:\Program Files\PostgreSQL\9.6\bin\psql.exe"
     
#>
Function Script-Constraints
{
param
(
	[Parameter(Mandatory=$true)]
[string]$server,
	[Parameter(Mandatory=$true)]
[string]$database,
	[Parameter(Mandatory=$true)]
[string]$puser,
[string]$ppwd,
	[Parameter(Mandatory=$true)]
[string]$scriptpath,
	[Parameter(Mandatory=$true)]
[string]$psqlpath = "C:\Program Files\PostgreSQL\9.6\bin\psql.exe" ,
[string]$schema="dbo"
)

#Primary & Foreign keys
# create the folder
if((Test-Path("$scriptpath\2_Constraints")) -eq $false)
{ New-Item -Path "$scriptpath\2_Constraints" -ItemType Directory}

$constraintpath = "$scriptpath\2_Constraints" 

#script out primary and foreign keys
$pkfkquery = "SELECT 'ALTER TABLE ' || '`"' || relname || '`"'|| ' ADD CONSTRAINT ' || '`"' || conname || '`" '|| pg_get_constraintdef(pg_constraint.oid)||';' AS keys FROM pg_constraint INNER JOIN pg_class ON conrelid=pg_class.oid INNER JOIN pg_namespace ON pg_namespace.oid=pg_class.relnamespace ORDER BY CASE WHEN contype='f' THEN 0 ELSE 1 END DESC,contype DESC,nspname DESC,relname DESC,conname DESC;" 
Write-Host "Scripting keys(Primary, Foreign & Unique) to $constraintpath\2_primary_foreign_unique_key.sql" -ForegroundColor Green
$pkfkresult = ExecuteQuery-PostgreSQL -server localhost -db $database -puser $puser -ppwd $ppwd -query $pkfkquery
$pkfkresult.keys | Out-File "$constraintpath\2_primary_foreign_unique_key.sql"


#script out check constraints
$ccquery = "SELECT 'Alter table `"' || tc.table_name || '`" ADD CONSTRAINT `"' || tc.constraint_name || '`" CHECK (' || cc.check_clause || ');' AS cc FROM information_schema.check_constraints as cc join information_schema.table_constraints as tc on cc.constraint_name=tc.constraint_name where tc.constraint_type='CHECK' and tc.constraint_schema!='pg_catalog' and tc.constraint_schema!='information_schema';"
$ccresult = ExecuteQuery-PostgreSQL -server localhost -db $database -puser $puser -ppwd $ppwd -query $ccquery
	Write-Host "Scripting check constraints to $constraintpath\1_check_constraints.sql" -ForegroundColor Green
$ccresult.cc | Out-File "$constraintpath\1_check_constraints.sql"


#script out sequences
$sqquery = "select `"sequence_schema`" || '.' || `"sequence_name`" AS seqname from Information_Schema.SEQUENCES;"
$sqresult = ExecuteQuery-PostgreSQL -server localhost -db $database -puser $puser -ppwd $ppwd -query $sqquery
$sq=""
foreach($row in $sqresult)
{
$schema=$row.seqname.split('.')[0];
$seqname = $row.seqname.split('.')[1];

$sqscript = "select 'CREATE SEQUENCE '|| `"sequence_name`" || ' AS BIGINT ' || ' START WITH ' || start_value || ' INCREMENT BY '|| increment_by || ' MINVALUE ' || min_value || ' MAXVALUE ' || max_value || CASE WHEN is_cycled='0' THEN ' NO CYCLE;' ELSE ' YES CYCLE;' END AS seqscript, ' ALTER SEQUENCE ' || sequence_name || ' RESTART WITH ' || last_value || ';' AS seqreset from $seqname;" 
$sq1result = ExecuteQuery-PostgreSQL -server localhost -db $database -puser $puser -ppwd $ppwd -query $sqscript
$sq= $sq + $nl + $sq1result.seqscript + $nl + $sq1result.seqreset
}

$sqpath = "$scriptpath\3_Sequences";
if((Test-Path("$sqpath")) -eq $false)
{ New-Item -Path "$sqpath" -ItemType Directory}
	Write-Host "Scripting sequences to $sqpath\sequences.sql" -ForegroundColor Green
$sq |   Out-File "$sqpath\sequences.sql"

}



<# 
 .Synopsis
  Create Azure resource group, azure sql server and azure sql database.

 .Description
  This function creates the azure sql server & azure sql database. Execute this if you want to 
  migrate the postgreSQL schema & data to Azure SQL Database and you don't have an existing 
  Azure SQL Database.

 .Parameter AzureProfilePath
  The path to the json file having your azure subscription details. This is required if you 
  don't want to enter azure credentials every time you run this function. This is optional

 .Parameter azuresqlservername
  The name of the azure sql server that'll host the azure sql database. The name should
  follow the standards.

 .Parameter resourcegroupname
  The resource group that will host the azure sql server.
 
 .Parameter databasename
  The azure sql server database name. 

 .Parameter login
  The login name for Azure sql server

 .Parameter password
  The password for the azure sql server login specified by the login parameter

 .Parameter location
  The Azure location/region to create the azure sql server

 .Parameter startip
  The startip to add to the firewall rule to Azure SQL Server. This is optional.

 .Parameter endip
  The endip to add to the firewall rule to Azure SQL Server. This is optional.

 .Example
  #Create an Azure SQL Database postgretosql in Azure SQL Server dplsrv in resourcegroup dpl.
  Create-AzureSQLDB -azuresqlservername="dplsrv" -resourcegroupname="dpl" -databasename="postgretosql" -login="dpladmin" -password="Awesome@0987" -location="Southeast Asia"
     
#>
function Create-AzureSQLDB{

param(
[string]$AzureProfilePath,
	[Parameter(Mandatory=$true)]
[string]$azuresqlservername,
	[Parameter(Mandatory=$true)]
[string]$resourcegroupname,
	[Parameter(Mandatory=$true)]
[string]$databasename,
	[Parameter(Mandatory=$true)]
[string]$login,
	[Parameter(Mandatory=$true)]
[string]$password,
	[Parameter(Mandatory=$true)]
[string]$location,
[string]$startip,
[string]$endip
)

TRY
{

	if([string]::IsNullOrEmpty($AzureProfilePath.Length))
	{ 
		# Log in to your Azure account. Enable this for the first time to get the Azure Credential
		Login-AzureRmAccount | Out-Null
	}
	else
	{
		#get profile details from the saved json file
		#enable if you have a saved profile
		$profile = Select-AzureRmProfile -Path $AzureProfilePath
		#Set the Azure Context
		$a=Set-AzureRmContext -SubscriptionId $profile.Context.Subscription.SubscriptionId 
	}

#Save your azure profile. This is to avoid entering azure credentials everytime you run a powershell script
#This is a json file in text format. If someone gets to this, you are done :)
#Save-AzureRmProfile -Path $AzureProfilePath | Out-Null

#check if resource group exists
$e = Get-AzureRmResourceGroup -Name $resourcegroupname -Location $location -ErrorAction SilentlyContinue -ErrorVariable rgerror
if($rgerror -ne $null)
{
Write-host "Provisioning Azure Resource Group $resourcegroupname... " -ForegroundColor Green
$b=New-AzureRmResourceGroup -Name $resourcegroupname -Location $location
Write-host "$resourcegroupname provisioned." -ForegroundColor Green
}

#create azure sql server if it doesn't exits
$f = Get-AzureRmSqlServer -ServerName $azuresqlservername -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue -ErrorVariable checkserver
if ($checkserver -ne $null) 
{ 
#create a sql server
Write-host "Provisioning Azure SQL Server $azuresqlservername ... " -ForegroundColor Green
$c=New-AzureRmSqlServer -ResourceGroupName $resourcegroupname -ServerName $azuresqlservername -Location $location -SqlAdministratorCredentials $(New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $login, $(ConvertTo-SecureString -String $password -AsPlainText -Force))
Write-host "$azuresqlservername provisioned." -ForegroundColor Green
}

#create a firewall rule
#get the public ip address
#this step will be skipped if startip & endip parameters are specified
if($startip -eq "" -or $endip -eq "")
{
#get the public ip
$ip = (Invoke-WebRequest http://myexternalip.com/raw -UseBasicParsing).Content.trim();

}

Write-host "Creating firewall rule for $azuresqlservername ... " -ForegroundColor Green
New-AzureRmSqlServerFirewallRule -ResourceGroupName $resourcegroupname  -ServerName $azuresqlservername -FirewallRuleName "Home" -StartIpAddress $ip -EndIpAddress $ip

#create sql database
Write-host "Creating Azure SQL database $databasename in $azuresqlservername ... " -ForegroundColor Green
$d=New-AzureRmSqlDatabase  -ResourceGroupName $resourcegroupname  -ServerName $azuresqlservername -DatabaseName $databasename -RequestedServiceObjectiveName "S0" -ErrorVariable sqldberr
Write-host "$databasename provisioned." -ForegroundColor Green
}
CATCH
{
Throw;
}
}


<# 
 .Synopsis
  Execute a query on a specified SQL Server

 .Description
  This function executes a query on a specified sql server. It is used to execute the schema files generated 
  by Script-Tables & Script-Constraints function.

 .Parameter server
  The SQL Server instance to run the query.

 .Parameter database
  The SQL Server database to run the query

 .Parameter user
  The SQL Server user name
 
 .Parameter pwd
  The password for the SQL Server login name specified by the user parameter 

 .Parameter query
  The query to be executed. This is optional.

 .Parameter file
  The .sql file to be executed. This is optional.

 .Parameter dir
  The directory path with .sql files to be executed. All the 
  .sql files in the dir are executed.

 .Example
  #Execute all .sql files in C:\Projects\Scripts directory.
  ExecuteQuery-SQLServer -server="win2012r2\SQL2014" -database="dbmigrate" -user="sa" -pwd="sql@2014" -dir="C:\Projects\Scripts"
     
#>
Function ExecuteQuery-SQLServer{

param(
	[Parameter(Mandatory=$true)]
[string]$server,
	[Parameter(Mandatory=$true)]
[string]$database,
	[Parameter(Mandatory=$true)]
[string]$user,
	[Parameter(Mandatory=$true)]
[string]$pwd,
[string]$query,
[string]$dir
)
	if($query.length -le 1 -and $dir.Length -le 1)
	{ Write-Host "Please provide a query, directory with .sql files to execute. "; return;}
	
	if($query.Length -gt 1)
	{
		Write-host "Executing query... " -ForegroundColor Green
		Invoke-SQLcmd -ServerInstance $server -Database $database -Username $user -Password $pwd -Query $query
		return;
	}
	$loc = Get-Location

	if($dir.Length -gt 1)
	{
		#execute all .sql files in a dir
		$sqlfiles = Get-ChildItem -Path $dir -Recurse -Include *.sql
		foreach($sql in $sqlfiles)
		{
			#execute the file
			Write-Host "Executing " $sql.FullName "..." -ForegroundColor Green
			Invoke-SQLcmd -ServerInstance $server -Database $database -Username $user -Password $pwd -InputFile $sql.FullName
		}
	#switch to the current location
	Set-Location $loc;
	}
}


<# 
 .Synopsis
  Import tab delimited files in sql server using bcp

 .Description
  This function imports all tab delimited data files in the specified sql server using bcp.
  The table name is same as the tab delimited file name.

 .Parameter server
  The SQL Server instance to run the query.

 .Parameter database
  The SQL Server database to run the query

 .Parameter user
  The SQL Server user name
 
 .Parameter pwd
  The password for the SQL Server login name specified by the user parameter 

 .Parameter dir
 The directory path with all data files to be imported into sql server

 .Parameter schema
 Specify the schema name for the tables in SQL Server. The default is dbo.

 .Parameter bcp
 The path of the bcp.exe on your system.

 .Parameter batchsize
 The batchsize for the bcp to use when bulk inserting data into sql server. The default is 5000.
 
 .Example
 #Import data into sql server from files in C:\Projects\Scripts folder
 Bcpin-SQLServer -server="win2012r2\SQL2014" -database="dbmigrate" -user="sa" -pwd="sql@2014" -dir="C:\Projects\Scripts"
     
#>
function Bcpin-SQLServer{
Param(
	[Parameter(Mandatory=$true)]
[string]$server,
	[Parameter(Mandatory=$true)]
[string]$database,
	[Parameter(Mandatory=$true)]
[string]$user,
	[Parameter(Mandatory=$true)]
[string]$pwd,
	[Parameter(Mandatory=$true)]
[string]$dir,
[string]$schema="dbo",
	[Parameter(Mandatory=$true)]
[string]$bcp,
[string]$batchsize = 5000
)



if((Test-Path $dir) -eq $false){ Write-host "Directory $dir doesn't exists." -ForegroundColor Green }

if((Test-Path $dir) -eq $true)
{ 
Write-host "Importing data from $dir into $server." -ForegroundColor Green
$items = Get-ChildItem -Path $dir -Include *.csv -Recurse
$arguments="";
foreach($item in $items)
{
Write-Host "Importing " + $item.Fullname "..." -ForegroundColor Green
$tablename = $item.BaseName.split(".")[1];
if($tablename -eq $null)
{ $tablename = $item.BaseName.split(".")[0]; }
$fullpath = $item.fullname

$arguments = " $schema.$tablename in `"$fullpath`" -c -k -t, -S $server -U $user -P $pwd -d $database -b $batchsize"
$arguments
Execute-Process -filepath $bcp -arguments $arguments

}

}

}


<# 
 .Synopsis
  Import csv files in sql server using bulk insert

 .Description
  This function imports a csv file into SQL Server using bulk insert. You can either import 
  a single csv file or all files in a specified directory. The csv file name should be same 
  as the SQL Server table name you are importing data into.

 .Parameter server
  The SQL Server instance to run the query.

 .Parameter database
  The SQL Server database to run the query

 .Parameter user
  The SQL Server user name
 
 .Parameter pwd
  The password for the SQL Server login name specified by the user parameter 

 .Parameter dir
 The directory path with csv files to be imported.

 .Parameter file
 The csv file to be imported.

 .Parameter schema
 Specify the schema name for the tables in SQL Server. The default is dbo.
 
 
 .Example
 #Import data into azure sql database from all csv files in C:\Projects\Migration\PostgrestoSQLServer\Data directory
 BulkInsert-SQLServer -server dplserver530.database.windows.net -database dvdrental -user dpladmin -pwd Awesome@0987 -dir "C:\Projects\Migration\PostgrestoSQLServer\Data"
     
#>
function BulkInsert-SQLServer{
	param(
		[Parameter(Mandatory=$true)]
[string]$server,
	[Parameter(Mandatory=$true)]
[string]$database,
	[Parameter(Mandatory=$true)]
[string]$user,
	[Parameter(Mandatory=$true)]
[string]$pwd,
[string]$dir,
[string]$file,
[string]$schema="dbo"
	)
	[System.Reflection.Assembly]::LoadFrom("C:\Users\Administrator\Documents\WindowsPowerShell\Modules\MigratePostgreSQLToSQLServer\CsvDataReader.dll") | Out-Null
	
	if([string]::IsNullOrEmpty($file) -and [string]::IsNullOrEmpty($dir))
	{
		Write-Host "Provide either a file or a directory path to import data" -ForegroundColor Red;
		return;
	}
	if(($file.Length -ge 5))
	{
		if((Test-Path $file) -eq $false)
		{ 
			Write-host "File $file doesn't exists." -ForegroundColor Red;
			return;
		}
		$tablename = (Get-Item -Path $file).Name
		$tablename = $tablename.Split('.')[0]
		$reader = New-Object SqlUtilities.CsvDataReader($file)
		$ConnectionString = "Data Source=$server;Initial Catalog=dvdrental;User ID=$user;Password=$pwd;"
		$bulkCopy = new-object ("Data.SqlClient.SqlBulkCopy") $ConnectionString
		$bulkCopy.DestinationTableName = $tablename
			Write-Host "Importing data into $tablename" -ForegroundColor Green;
		$bulkCopy.WriteToServer($reader);
		return;
	}

	if($dir.Length -ge 5)
	{
		if((Test-Path $dir) -eq $false)
		{ 
			Write-host "Directory $dir doesn't exists." -ForegroundColor Red;
			return;
		}
	

	if((Test-Path $dir) -eq $true)
	{ 
		Write-host "Importing data from $dir into $server" -ForegroundColor Green
		$items = Get-ChildItem -Path $dir -Include *.csv -Recurse
		foreach($item in $items)
		{
			Write-Host "Importing " $item.Fullname "..." -ForegroundColor Green
			$tablename = $item.BaseName.split(".")[1];
			if($tablename -eq $null)
			{ 
				$tablename = $item.BaseName.split(".")[0]; 
			}
			$fullpath = $item.fullname
			
			$reader = New-Object SqlUtilities.CsvDataReader($fullpath)
			$ConnectionString = "Data Source=$server;Initial Catalog=dvdrental;User ID=$user;Password=$pwd;"
			$bulkCopy = new-object ("Data.SqlClient.SqlBulkCopy") $ConnectionString
			$bulkCopy.DestinationTableName = $tablename
			$bulkCopy.WriteToServer($reader);
		}
	}
	}
}

