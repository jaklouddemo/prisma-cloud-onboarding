# Synopsis

PowerShell scripts used to create Prisma Cloud roles in public cloud accounts along with registering each account in Prisma Cloud

## AWS

### Script

aws/OnBoard-PrismaCloud-AWS.ps1

### Arguments

pcApiAccessKeyId = Prisma Cloud API Access Key ID
pcApiSecretKey = Prisma Cloud API Secret Key

### Input File

aws/aws-accounts.csv
-- For each AWS account - add: accountName,accessKey,secretKey,region

## Azure

### Script

azure/OnBoard-PrismaCloud-Azure.ps1

### Arguments

None

### Input File

None


