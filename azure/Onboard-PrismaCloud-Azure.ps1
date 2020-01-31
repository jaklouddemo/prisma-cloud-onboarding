param (
    [string]$pcApiAcctId = $( Read-Host -asSecureString "Input Prisma Cloud API Account ID" ),
    [string]$pcApiSecretKey = $( Read-Host -asSecureString "Input Prisma Cloud API Secret Key" )
  )
  
# Update $pcUriBase to match tenant #, for example https://app3.prismacloud.io = https://api3.prismacloud.io/
$pcUriBase = "https://api3.prismacloud.io/"

# Check if appropriate Azure PowerShell modules installed and imported
if (!(Get-Module -Name Az -ListAvailable)) {
  Install-Module -Name Az -AllowClobber -Scope CurrentUser
  }
elseif (!(Get-Module -Name Az)) {
  Import-Module Az
}
elseif (!(Get-Module -Name Az.Resources -ListAvailable)) {
  Install-Module -Name Az.Resources -AllowClobber -Scope CurrentUser
}
elseif (!(Get-Module -Name Az.Resources)) {
  Import-Module Az.Resources
}

$basePath = (Get-Location).Path

# Prisma Cloud static variables for Azure
$azAppHomeUrl   = "https://www.redlock.io"
$azAppHomeUrl2  = "https://redlock.io"
$azRoles        = @("Reader", "Reader and Data Access", "Storage Account Contributor", "Network Contributor", "Security Reader")
$pcPrefix       = "PrismaCloud-"
$pcAzJsonConfigs    = New-Object -TypeName System.Collections.ArrayList

$pcAzReportObjs = New-Object -TypeName System.Collections.ArrayList
$pcJsonCloudAcctFiles = New-Object -TypeName System.Collections.ArrayList

# Function to create secure object called by Create-AesKey function
function Create-AesManagedObject($key, $IV) {

  $aesManaged = New-Object "System.Security.Cryptography.AesManaged"
  $aesManaged.Mode = [System.Security.Cryptography.CipherMode]::CBC
  $aesManaged.Padding = [System.Security.Cryptography.PaddingMode]::Zeros
  $aesManaged.BlockSize = 128
  $aesManaged.KeySize = 256

  if ($IV) {
      if ($IV.getType().Name -eq "String") {
          $aesManaged.IV = [System.Convert]::FromBase64String($IV)
      }
      else {
          $aesManaged.IV = $IV
      }
  }

  if ($key) {
      if ($key.getType().Name -eq "String") {
          $aesManaged.Key = [System.Convert]::FromBase64String($key)
      }
      else {
          $aesManaged.Key = $key
      }
  }
  $aesManaged
}

function Create-AesKey() {
  $aesManaged = Create-AesManagedObject 
  $aesManaged.GenerateKey()
  [System.Convert]::ToBase64String($aesManaged.Key)
}

# Get Prisma Cloud Auth Token
$pcLoginHeader  = @{ 'Content-Type' = 'application/json' }
$pcLoginBody    = @{ 'username' = $pcApiAcctId; 'password' = $pcApiSecretKey } | ConvertTo-Json
$pcLoginToken   = (Invoke-RestMethod -Uri ($pcUriBase + "login") -Method "POST" -Header $pcLoginHeader -Body $pcLoginBody).token
$pcHeader = @{ 'Content-Type' = 'application/json'; 'x-redlock-auth' = $pcLoginToken}

# Get Prisma Cloud Default Account Group Id
$pcGroupIds     = Invoke-RestMethod -Uri ($pcUriBase + "cloud/group") -Method "GET" -Header $pcHeader
$pcDefaultGroupId = "[ `"" + ($pcGroupIds | ? {$_.name -eq "Default Account Group"}).id  + "`" ]"

$azSubs = Get-AzSubscription
$azAcctName = $azSubs | select -ExpandProperty ExtendedProperties | %{ $_.Values } | select -First 1
foreach ($azSub in $azSubs) {
  $logPrefixStr = ""
  $azSubId    = $azSub.Id
  $azSubName  = $azSub.Name
  $logPrefixStr = "[ " + $azSubName + " ]:"
  $azAppName  = $pcPrefix + $azSubName
  Set-AzContext -SubscriptionId $azSubId | Out-Null
  if (!(Get-AzADApplication -DisplayName $azAppName) -and (!($excludedAzSubIds.Contains($azSubId)))) {
    Write-Host $logPrefixStr "Working on Azure Subscription ID"
    $keyValue       = Create-AesKey
    $psadCredential = New-Object Microsoft.Azure.Commands.ActiveDirectory.PSADPasswordCredential
    $startDate      = Get-Date
    $psadCredential.StartDate = $startDate
    $psadCredential.EndDate = Get-Date("12/31/2099")
    $psadCredential.KeyId = [guid]::NewGuid()
    $psadCredential.Password = $keyValue
    $azAppUri       = "http://" + $azAppName + "/"
    $azReplyURLs    = @($azAppUri, $azAppHomeUrl, $azAppHomeUrl2)
    Write-Host $logPrefixStr "Creating Application Registration"
    $azApp          = New-AzADApplication -DisplayName $azAppName `
                      -IdentifierUris $azAppUri `
                      -Homepage $azAppHomeUrl `
                      -ReplyUrls $azReplyURLs `
                      -PasswordCredentials $psadCredential
    $azAppKey       = $keyValue
    $azAppApplicationId = $azApp.ApplicationId
    $azSubTenantId  = $azSub.TenantId
    Write-Host $logPrefixStr "Creating ServicePrincipal"
    New-AzADServicePrincipal -ApplicationId $azApp.ApplicationId | Out-Null
    Write-Host $logPrefixStr "Assigning roles to ServicePrincipal (waiting 60 seconds for SP creation)"
    Start-Sleep 60
    $azSpId         = (Get-AzADServicePrincipal -DisplayName $azAppName).Id
    foreach ($roleName in $azRoles) {
      Write-Host $logPrefixStr "Adding role to ServicePrincipal: $roleName"
      New-AzRoleAssignment -RoleDefinitionName $roleName -ApplicationId $azApp.ApplicationId | Out-Null
      Start-Sleep 1
      }
    $pcAzReportObj = "" | select "AzureParentAccount", "AzureSubscriptionName", "CloudAccountName", "CloudType", "SubscriptionID", "ActiveDirectoryID", "ApplicationID", "ApplicationKey", "AzureServicePrincipalID", "MonitorNSGFlowLogs", "AccountGroupsID", "AccountEnabled"
    $pcAzReportObj.AzureParentAccount = $azAcctName
    $pcAzReportObj.AzureSubscriptionName = $azSubName
    $pcAzReportObj.CloudAccountName = $azAppName
    $pcAzReportObj.CloudType = "azure"
    $pcAzReportObj.SubscriptionID = $azSubId
    $pcAzReportObj.ActiveDirectoryID = $azSubTenantId
    $pcAzReportObj.ApplicationID = $azAppApplicationId
    $pcAzReportObj.ApplicationKey = $azAppKey
    $pcAzReportObj.AzureServicePrincipalID = $azSpId
    $pcAzReportObj.MonitorNSGFlowLogs = "true"
    $pcAzReportObj.AccountGroupsID = $pcDefaultGroupId
    $pcAzReportObj.AccountEnabled = "true"
    [Void]$pcAzReportObjs.Add($pcAzReportObj)
$pcAzJsonConfig = @"
{
  "cloudAccount": {
    "accountId": "$azSubId",
    "enabled": true,
    "groupIds": $pcDefaultGroupId,
    "name": "$azAppName"
  },
  "clientId": "$azAppApplicationId",
  "key": "$azAppKey",
  "monitorFlowLogs": true,
  "tenantId": "$azSubTenantId",
  "servicePrincipalId": "$azSpId"
}
"@

    [Void]$pcAzJsonConfigs.Add($pcAzJsonConfig)
    }
    else {
      Write-Host $logPrefixStr "Application name: $azAppName already exists or Azure Subscription ID is explicitly excluded in list excludedAzSubIds"
      }
  }

# Write CSV report
$pcAzReportObjs | Export-Csv -Path "./report.csv" -NoTypeInformation

foreach ($pcCloudAcct in $pcAzJsonConfigs) {
  $pcCloudAcctName = ($pcCloudAcct | ConvertFrom-Json | Select-Object -ExpandProperty "cloudAccount").name
  $jsonFileName = $pcCloudAcctName + "-CloudAcctConfig.json"
  $jsonFilePath = Join-Path -Path $basePath -ChildPath $jsonFileName
  [Void]$pcJsonCloudAcctFiles.Add($jsonFilePath)
  $pcCloudAcct | Out-File -FilePath $jsonFilePath -Encoding utf8
  }
Write-Host $logPrefixStr "Please update each of the following JSON files 'key' attribute with client secret created in the Azure Portal"
$pcJsonCloudAcctFiles
Write-Host $logPrefixStr "Press any key to continue once all the JSON files are updated"
Read-Host

foreach ($jsonFile in $pcJsonCloudAcctFiles) {
  $fileShortName = $jsonFile | Split-Path -Leaf
  Write-Host "[ " + $fileShortName + " ] Creating Prisma Cloud Account"
  $body = Get-Content -Path $jsonFile
  Invoke-RestMethod -Uri ($pcUriBase + "cloud/azure") -Method "POST" -Header $pcHeader -Body $body
  }

# Azure cleanup command
# Get-AzADApplication | ? { $_.DisplayName -match "^PrismaCloud" } | Remove-AzADApplication