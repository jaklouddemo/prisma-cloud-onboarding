param (
    [string]$pcApiAccessKeyId = $( Read-Host -asSecureString "Input Prisma Cloud API Account ID" ),
    [string]$pcApiSecretKey = $( Read-Host -asSecureString "Input Prisma Cloud API Secret Key" )
  )
  
  # Update $pcUriBase to match tenant #, for example https://app3.prismacloud.io = https://api3.prismacloud.io/
$pcUriBase = "https://api3.prismacloud.io/"
$awsCreds = Import-Csv -Path "./aws-accounts.csv"
$awsRoleName = "PrismaCloud-ReadOnlyRole"
$awsInlinePolicyName = $awsRoleName + "-Policy"

foreach ($awsCred in $awsCreds) {
  $awsAcctName    = $awsCred.accountName
  Set-AWSCredential -AccessKey $awsCred.accessKey -SecretKey $awsCred.secretKey
  Set-DefaultAWSRegion $awsCred.regiond
  $awsManagedPolicyArn = "arn:aws:iam::aws:policy/SecurityAudit"
  $awsAcctId      = (Get-IAMUsers | select -First 1).Arn.Split(":")[4]
  $awsExternalId  = -join ((65..90) + (97..122) | Get-Random -Count 12 | % {[char]$_})

  $awsBaseRolePolicyDoc = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::188619942792:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "$awsExternalId"
        }
      }
    }
  ]
}
"@

  $awsInlineRolePolicyDoc = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "apigateway:GET",
        "cognito-identity:ListTagsForResource",
        "cognito-idp:ListTagsForResource",
        "elasticbeanstalk:ListTagsForResource",
        "elasticfilesystem:DescribeTags",
        "glacier:GetVaultLock",
        "glacier:ListTagsForVault",
        "logs:GetLogEvents",
        "mq:listBrokers",
        "mq:describeBroker",
        "secretsmanager:DescribeSecret",
        "ssm:GetParameters",
        "ssm:ListTagsForResource",
        "sqs:SendMessage",
        "elasticmapreduce:ListSecurityConfigurations",
        "sns:listSubscriptions"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
"@

  $awsNewIamRole = New-IAMRole -AssumeRolePolicyDocument $awsBaseRolePolicyDoc -RoleName $awsRoleName
  $awsRoleArn = $awsNewIamRole.Arn

  Register-IAMRolePolicy -RoleName $awsRoleName -PolicyArn $awsManagedPolicyArn
  Write-IAMRolePolicy -RoleName $awsRoleName -PolicyName $awsInlinePolicyName -PolicyDocument $awsInlineRolePolicyDoc

  # Prisma Cloud - Get Auth Token
  $pcLoginHeader  = @{ 'Content-Type' = 'application/json' }
  $pcLoginBody    = @{ 'username' = $pcApiAccessKeyId; 'password' = $pcApiSecretKey } | ConvertTo-Json
  $pcLoginToken   = (Invoke-RestMethod -Uri ($pcUriBase + "login") -Method "POST" -Header $pcLoginHeader -Body $pcLoginBody).token
  $pcHeader = @{ 'Content-Type' = 'application/json'; 'x-redlock-auth' = $pcLoginToken}

  # Prisma Cloud - Get Default Account Group Id
  $pcGroupIds     = Invoke-RestMethod -Uri ($pcUriBase + "cloud/group") -Method "GET" -Header $pcHeader
  $pcDefaultGroupId = "[ `"" + ($pcGroupIds | ? {$_.name -eq "Default Account Group"}).id  + "`" ]"

  $pcAddCloudAcctBody = @"
{
  "accountId": "$awsAcctId",
  "enabled": true,
  "externalId": "$awsExternalId",
  "groupIds": $pcDefaultGroupId,
  "name": "$awsAcctName",
  "roleArn": "$awsRoleArn"
}
"@
  # Prisma Cloud - Add Cloud Account
  Invoke-RestMethod -Uri ($pcUriBase + "cloud/aws") -Method "POST" -Header $pcHeader -Body $pcAddCloudAcctBody
  }
