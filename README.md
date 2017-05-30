# MigratePostgreSQLToSQLServer
Migrate Table Schema and Data from PostgreSQL to SQL Server (Azure & On-Premise) in 4 easy steps

Download and copy the module to your module directory. To find out the default module directory execute the below powershell command 

$env:PSModulePath

Import the module using the below command

Import-Module MigratePostgreSQLToSQLServer

Execute the below steps to migrate schema and data from PostgreSQL to SQL Server

1. Script tables creation and data from PostgreSQL to .sql and csv files respectively

The function Script-Table scripts out tables in T-SQL format and exports the table data in csv format from postgreSQL database dvdrental.

Script-Table -datapath "C:\Projects\Migration\PostgrestoSQLServer\Data" -server localhost -database dvdrental ` 
-puser postgres -ppwd postgres -scriptpath "C:\Projects\Migration\PostgrestoSQLServer\Schema" -psqlpath "C:\Program Files\PostgreSQL\9.6\bin\psql.exe"


2. Script constraint and sequences in T-SQL format from PostgreSQL

The Script-Constraints function scripts out the primary, foreign and unique keys, check constraint and sequences in SQL Server format. 

Script-Constraints -server localhost -database dvdrental -puser postgres -ppwd postgres -scriptpath "C:\Projects\Migration\PostgrestoSQLServer\Schema" 

3. Create table and constraints in the sql server database using the scripts created in previous steps

The function ExecuteQuery-SQLServer executes all the .sql file in the specified directory to a give sql server. This can be an on premise, Azure SQL Database or a 
SQLServer on Azure VM. 

ExecuteQuery-SQLServer -server dplserver530.database.windows.net -database dvdrental -user dpladmin ` 
-pwd Awesome@0987 -dir "C:\Projects\Migration\PostgrestoSQLServer\Schema"

4. Import the data from the csvs exported from PostgreSQL in previous steps

The function BulkInsert-SQLServer imports all the csvs into SQL Server in a given directory. The name of the csv file should match the name of the table.
Specifiy the -file parameter instead of -dir to import the data from a single file.

BulkInsert-SQLServer -server dplserver530.database.windows.net -database dvdrental -user dplamin ` 
-pwd Awesome@0987 -dir "C:\Projects\Migration\PostgrestoSQLServer\Data"

5. Additional Function to create the azure sql database 

If you are trying this out on an Azure SQL Database and you don't have an existing Azure SQL DB, you can use the below function to provision one

Create-AzureSQLDB -AzureProfilePath "C:\Projects\70475\AzureProfile\azureprofile.json" -azuresqlservername dplsrv19054 `
-resourcegroupname dpl -databasename dvdrental -login dpladmin -password Awesome@0987 -location "Southeast Asia"


