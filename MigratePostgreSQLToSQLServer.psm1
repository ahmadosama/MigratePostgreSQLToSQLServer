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
[string]$filepath,
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
Write-Host "stdout: $stdout"
Write-Host "stderr: $stderr"
Write-Host "exit code: " + $p.ExitCode
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
  $result = ExecuteQuery-PostgreSQL -server $server -db $db -puser postgres -ppwd postgres -query $query
  #do something with $results.
     
#>
function ExecuteQuery-PostgreSQL{
   param([string]$query,
   [string]$server,
   [string]$db,
   [string]$puser,
   [string]$ppwd
   )
   $conn = New-Object System.Data.Odbc.OdbcConnection
   $conn.ConnectionString = "Driver={PostgreSQL ODBC Driver(UNICODE)};Server=$server;Database=$db;Uid=$puser;Pwd=$ppwd;"
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
[string]$datapath="C:\Projects\Migration\PostgrestoSQLServer\Data",
[string]$server="localhost",
[string]$db="mydb",
[string]$puser="postgres",
[string]$ppwd="postgres",
[string]$scriptpath="C:\Projects\Migration\PostgrestoSQLServer\Schema",
[string]$psqlpath = "C:\Program Files\PostgreSQL\9.6\bin\psql.exe",
[string]$schema="dbo",
[string]$scriptoptions="all" #schema/data/all
)

#create destination directory if it doesn't exists
if((Test-Path("$scriptpath\1_Tables")) -eq $false)
{ New-Item -Path "$scriptpath\1_Tables" -ItemType Directory | Out-Null}

$scriptpath = "$scriptpath\1_Tables" 

#get tables to export
$query = "select table_schema || '.' || table_name As tablename from information_schema.tables where table_type = 'BASE TABLE' and table_schema != 'pg_catalog' AND table_schema != 'information_schema';"
$result = ExecuteQuery-PostgreSQL -server $server -db $db -puser postgres -ppwd postgres -query $query

$nl = [Environment]::NewLine;


$tablename=""
foreach($tbl in $result)
{
$tblfullname = $tbl.tablename;
$tablename = $tbl.tablename.Split('.')[1];


#script data
if($scriptoptions -eq "All" -or $scriptoptions -eq "data")
{
$tsvpath = ($datapath + "\" + $tablename + ".tsv").Replace("\","\\");
#psql -h localhost -U postgres -d mydb  -c "COPY (select * from site_users) TO E'C:\\Projects\\Migration\\PostgrestoSQLServer\\Data\\csv\\site_users'  WITH CSV DELIMITER E'\t'"
$argument = "-h $server -U $puser -d $db -c `"COPY $tblfullname TO E'$tsvpath' WITH CSV DELIMITER E'\t'"
$argument
Execute-Process -filepath $psqlpath -arguments $argument
}


$colquery = "SELECT table_name,column_name,column_default,is_nullable,data_type,character_maximum_length,numeric_precision,udt_name from Information_Schema.Columns where table_name='$tablename';"
$colresult = ExecuteQuery-PostgreSQL -server localhost -db mydb -puser postgres -ppwd postgres -query $colquery
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
{ $dt = "bigint" }
elseif ($col.udt_name -eq "int4")
{ $dt= "int" }
elseif ($col.udt_name -eq "timestamptz")
{ $dt= "datetime2"}
elseif ($col.udt_name -eq "bool")
{ $dt= "varchar(5)"}
elseif ($col.udt_name -eq "text")
{ $dt= "nvarchar(max)"}
else
{$dt=$col.udt_name;}

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
[string]$server="localhost",
[string]$db="mydb",
[string]$puser="postgres",
[string]$ppwd="postgres",
[string]$scriptpath="C:\Projects\Scripts\",
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
$pkfkresult = ExecuteQuery-PostgreSQL -server localhost -db mydb -puser postgres -ppwd postgres -query $pkfkquery
$pkfkresult.keys | Out-File "$constraintpath\2_primary_foreign_unique_key.sql"


#script out check constraints
$ccquery = "SELECT 'Alter table `"' || tc.table_name || '`" ADD CONSTRAINT `"' || tc.constraint_name || '`" CHECK (' || cc.check_clause || ');' AS cc FROM information_schema.check_constraints as cc join information_schema.table_constraints as tc on cc.constraint_name=tc.constraint_name where tc.constraint_type='CHECK' and tc.constraint_schema!='pg_catalog' and tc.constraint_schema!='information_schema';"
$ccresult = ExecuteQuery-PostgreSQL -server localhost -db mydb -puser postgres -ppwd postgres -query $ccquery
$ccresult.cc | Out-File "$constraintpath\1_check_constraints.sql"


#script out sequences
$sqquery = "select `"sequence_schema`" || '.' || `"sequence_name`" AS seqname from Information_Schema.SEQUENCES;"
$sqresult = ExecuteQuery-PostgreSQL -server localhost -db mydb -puser postgres -ppwd postgres -query $sqquery
$sq=""
foreach($row in $sqresult)
{
$schema=$row.seqname.split('.')[0];
$seqname = $row.seqname.split('.')[1];

$sqscript = "select 'CREATE SEQUENCE '|| `"sequence_name`" || ' AS BIGINT ' || ' START WITH ' || start_value || ' INCREMENT BY '|| increment_by || ' MINVALUE ' || min_value || ' MAXVALUE ' || max_value || CASE WHEN is_cycled='0' THEN ' NO CYCLE;' ELSE ' YES CYCLE;' END AS seqscript, ' ALTER SEQUENCE ' || sequence_name || ' RESTART WITH ' || last_value || ';' AS seqreset from $seqname;" 
$sq1result = ExecuteQuery-PostgreSQL -server localhost -db mydb -puser postgres -ppwd postgres -query $sqscript
$sq= $sq + $nl + $sq1result.seqscript + $nl + $sq1result.seqreset
}

$sqpath = "$scriptpath\3_Sequences";
if((Test-Path("$sqpath")) -eq $false)
{ New-Item -Path "$sqpath" -ItemType Directory}

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
[string]$AzureProfilePath="C:\Projects\70475\AzureProfile\azureprofile.json",
[string]$azuresqlservername="dplsrv",
[string]$resourcegroupname="dpl",
[string]$databasename="postgretosql",
[string]$login="dpladmin",
[string]$password="Awesome@0987",
[string]$location="Southeast Asia",
[string]$startip="",
[string]$endip=""
)

TRY
{
# Log in to your Azure account. Enable this for the first time to get the Azure Credentials
#Login-AzureRmAccount | Out-Null

#Save your azure profile. This is to avoid entering azure credentials everytime you run a powershell script
#This is a json file in text format. If someone gets to this, you are done :)
#Save-AzureRmProfile -Path $AzureProfilePath | Out-Null

#get profile details from the saved json file
#enable if you have a saved profile
$profile = Select-AzureRmProfile -Path $AzureProfilePath

#Set the Azure Context
Set-AzureRmContext -SubscriptionId $profile.Context.Subscription.SubscriptionId 

#check if resource group exists
Get-AzureRmResourceGroup -Name $resourcegroupname -Location $location -ErrorAction SilentlyContinue -ErrorVariable rgerror
if($rgerror -ne $null)
{
Write-host "Creating Azure Resource Group $resourcegroupname... " -ForegroundColor Green
New-AzureRmResourceGroup -Name $resourcegroupname -Location $location
}

#create azure sql server if it doesn't exits
Get-AzureRmSqlServer -ServerName $azuresqlservername -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue -ErrorVariable checkserver
if ($checkserver -ne $null) 
{ 
#create a sql server
Write-host "Creating Azure SQL Server $azuresqlservername ... " -ForegroundColor Green
New-AzureRmSqlServer -ResourceGroupName $resourcegroupname -ServerName $azuresqlservername -Location $location -SqlAdministratorCredentials $(New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $login, $(ConvertTo-SecureString -String $password -AsPlainText -Force))

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
New-AzureRmSqlDatabase  -ResourceGroupName $resourcegroupname  -ServerName $azuresqlservername -DatabaseName $databasename -RequestedServiceObjectiveName "S0" -ErrorVariable sqldberr
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
[string]$server="win2012r2\SQL2014",
[string]$database="dbmigrate",
[string]$user="sa",
[string]$pwd="sql@2014",
[string]$query="",
[string]$file="",
[string]$dir="C:\Projects\Scripts"
)

#execute all .sql files in a dir
$sqlfiles = Get-ChildItem -Path $dir -Recurse -Include *.sql
foreach($sql in $sqlfiles)
{
#execute the file
Write-Host $sql.FullName
Invoke-SQLcmd -ServerInstance $server -Database $database -Username $user -Password $pwd -InputFile $sql.FullName


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
 The directory path with .sql files to be executed. All the 
 .sql files in the dir are executed.

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
[string]$server="win2012r2\SQL2014",
[string]$database="dbmigrate",
[string]$user="sa",
[string]$pwd="sql@2014",
[string]$dir="C:\Projects\Scripts",
[string]$schema="dbo",
[string]$bcp = "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\bcp.exe",
[string]$batchsize = 5000
)



if((Test-Path $dir) -eq $false){ Write-host "Directory $dir doesn't exists." -ForegroundColor Green }

if((Test-Path $dir) -eq $true)
{ 
Write-host "Importing data from $dir into $server." -ForegroundColor Green
$items = Get-ChildItem -Path $dir -Include *.tsv -Recurse
$arguments="";
foreach($item in $items)
{
Write-Host "Importing $item.Fullname..."
$tablename = $item.BaseName.split(".")[1];
if($tablename -eq $null)
{ $tablename = $item.BaseName.split(".")[0]; }
$fullpath = $item.fullname

$arguments = " $schema.$tablename in `"$fullpath`" -c -S $server -U $user -P $pwd -d $database -b $batchsize"
$arguments
Execute-Process -filepath $bcp -arguments $arguments

}

}

}

