# Check if Azure CLI is installed and user is logged in
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. Please install it first."
    exit 1
}

# Variables

# manually deploy 
- resource group
- vnet with 3 subnets, 1 for private endpoint, 1 for vnet integration, 1 for vm testing
- logic app with private endpoint and vnet integration 
- function app with private endpoint and vnet integration
- both logic app and function app will use the subnet created 
- function app and storage account will have their own storage account (storage account created when creating the resource in the portal)
- once both are deployed the following script will help to configure the function app and logic app
- all values below will come from the manually created resources

# run this in a powershell window. you need to be logged into appropriate subscription
# need to run from a machine that has "line of sight" of the resources created in the portal
# need to have az cli installed and logged in

# Variables - all from manually created resources
$resourceGroup = "RESOURCEGROUPNAME"
$location = "LOCATION"
$workspaceName =  "WORKSPACENAME"
$appInsightsName = "APPINSIGHTNAME"
$logicAppName = "LOGICAPPNAME"
$functionAppName = "FUNCTIONAPPNAME"
$functionRuntime = "dotnet-isolated"
$functionVersion = "8"
$funcAppServicePlan = "FUNCTIONAPPSERVICEPLANNAME"
$logicAppPlan ="LOGICAPPLANNAME"
$funcStorageAccount = "FUNCTIONSTORAGEACCOUNTNAME"
$logicAppstorageAccount="LOGICAPPSTORAGEACCOUNTNAME"




# Get Logic App Storage Account Key
$logicAppstorageKey = $(az storage account keys list `
    --resource-group $resourceGroup `
    --account-name $logicAppstorageAccount `
    --query '[0].value' -o tsv)

Write-Host "Logic App Storage Account Key: $logicAppstorageKey" -ForegroundColor Yellow




# Get Function Storage Account Key
$funcstorageKey = $(az storage account keys list `
    --resource-group $resourceGroup `
    --account-name $funcStorageAccount `
    --query '[0].value' -o tsv)

Write-Host "Function Storage Account Key: $funcstorageKey" -ForegroundColor Yellow




# Create Queues and Tables in Function Storage Account
Write-Host "Creating Queues and Tables in Function Storage Account..." -ForegroundColor Green

# Create Queues
$queues = @(
    "create-alert-request",
    "orchestration-request",
    "execution-request",
    "savings-request-queue",
    "auto-update-request-queue"
)

foreach ($queue in $queues) {
    Write-Host "Creating Queue: $queue" -ForegroundColor Yellow
    az storage queue create `
        --name $queue `
        --account-name $funcStorageAccount `
        --account-key $funcstorageKey
}

# Create Tables
$tables = @(
    "requeststoretable",
    "subscriptionrequeststoretable",
    "autoupdaterequestdetailsstoretable"
)

foreach ($table in $tables) {
    Write-Host "Creating Table: $table" -ForegroundColor Yellow
    az storage table create `
        --name $table `
        --account-name $funcStorageAccount `
        --account-key $funcstorageKey
}



# assigned managed identity to Function App 



az functionapp identity assign `
    --name $functionAppName `
    --resource-group $resourceGroup `
    --identities [system]

# Get Function App managed identity principal ID
$functionAppPrincipalId = $(az functionapp identity show `
    --name $functionAppName `
    --resource-group $resourceGroup `
    --query principalId `
    --output tsv)

Write-Host "Function App Principal ID: $functionAppPrincipalId" -ForegroundColor Yellow


# Enable managed identity for Logic App. Not required but good practice
Write-Host "Enabling managed identity for Logic App..." -ForegroundColor Green
az functionapp identity assign `
    --name $logicAppName `
    --resource-group $resourceGroup `
    --identities [system]

# Get Logic App managed identity principal ID
$logicAppPrincipalId = $(az functionapp identity show `
    --name $logicAppName `
    --resource-group $resourceGroup `
    --query principalId `
    --output tsv)

Write-Host "Logic App Principal ID: $logicAppPrincipalId" -ForegroundColor Yellow

# grant the function app identity contributor access to the subscription
# better to create custom role with correct permissions
$subscriptionId=$(az account show --query id -o tsv)
az role assignment create --role "Contributor" --assignee $functionAppPrincipalId --scope "/subscriptions/$subscriptionId"





# Output the important resource names for reference
Write-Host "Logic Storage Account Name: $logicAppstorageAccount" -ForegroundColor Yellow
Write-Host "Function App Name: $functionAppName" -ForegroundColor Yellow
Write-Host "Logic App Name: $logicAppName" -ForegroundColor Yellow

# Download StartStopV2.zip
Write-Host "Downloading StartStopV2.zip..." -ForegroundColor Green
Invoke-WebRequest -Uri "https://github.com/microsoft/startstopv2-deployments/raw/refs/heads/main/artifacts/StartStopV2.zip" -OutFile "StartStopV2.zip"

# deploy StartStopV2.zip to function app
Write-Host "Deploying function app code..." -ForegroundColor Green
az functionapp deployment source config-zip `
    --name $functionAppName `
    --resource-group $resourceGroup `
    --src StartStopV2.zip

# deploy la.zip to logic app
Write-Host "Deploying logic app code..." -ForegroundColor Green

az logicapp deployment source config-zip `
    --name $logicAppName `
    --resource-group $resourceGroup `
    --src lav2.zip



# stop functionapp
Write-Host "Stopping function app..." -ForegroundColor Green
az functionapp stop --name $functionAppName --resource-group $resourceGroup

# get the subscription id, tenant id, and app key for app insights
$subscriptionId = $(az account show --query id -o tsv)
$tenantId=$(az account show --query tenantId -o tsv)
$appInsightsInstrumentionKey=$(az monitor app-insights component show --app $appInsightsName --resource-group $resourceGroup --query "instrumentationKey" -o tsv)

# get the function storage connection string
$funcstorageKey2 = $(az storage account keys list --resource-group $resourceGroup --account-name $funcStorageAccount --query '[0].value' -o tsv)
Write-Host "Function Storage Account Key: $funcstorageKey2" -ForegroundColor Yellow
# Get function storage account connection string
$funcStorageConnectionString = $(az storage account show-connection-string `
    --name $funcStorageAccount `
    --resource-group $resourceGroup `
    --query connectionString `
    --output tsv)

Write-Host "Function Storage Connection String: $funcStorageConnectionString" -ForegroundColor Yellow





# Set all Function App settings in a single command
Write-Host "Configuring Function App settings..." -ForegroundColor Green
az functionapp config appsettings set `
    --name $functionAppName `
    --resource-group $resourceGroup `
    --settings `
    "AzureClientOptions:SubscriptionId=$subscriptionId" `
    "AzureClientOptions:ResourceGroup=$resourceGroup" `
    "AzureClientOptions:ResourceGroupRegion=$location" `
    "AzureClientOptions:FunctionAppName=$functionAppName" `
    "AzureClientOptions:TenantId=$tenantId" `
    "AzureClientOptions:AzureEnvironment=AzureGlobalCloud" `
    "StorageOptions:StorageAccountConnectionString=$funcStorageConnectionString" `
    "StorageOptions:CreateAutoStopAlertRequestQueue=create-alert-request" `
    "StorageOptions:OrchestrationRequestQueue=orchestration-request" `
    "StorageOptions:ExecutionRequestQueue=execution-request" `
    "StorageOptions:SavingsRequestQueue=savings-request-queue" `
    "StorageOptions:AutoUpdateRequestQueue=auto-update-request-queue" `
    "StorageOptions:RequestStoreTable=requeststoretable" `
    "StorageOptions:SubscriptionRequestStoreTable=subscriptionrequeststoretable" `
    "StorageOptions:AutoUpdateRequestDetailsStoreTable=autoupdaterequestdetailsstoretable" `
    "CentralizedLoggingOptions:InstrumentationKey=$appInsightsInstrumentionKey" `
    "CentralizedLoggingOptions:Version=1.1.20241024.1" `
    "AzureClientOptions:ApplicationInsightName=$appInsightsName" `
    "AzureClientOptions:ApplicationInsightRegion=$location" `
    "AzureClientOptions:AutoUpdateTemplateUri=https://raw.githubusercontent.com/microsoft/startstopv2-deployments/main/artifacts/ssv2autoupdate.json" `
    "AzureClientOptions:AutoUpdateRegionsUri=https://raw.githubusercontent.com/microsoft/startstopv2-deployments/main/artifacts/AutoUpdateRegionsGA.json" `
    "AzureClientOptions:StorageAccountName=$funcStorageAccount" `
    "AzureClientOptions:Version=1.1.20241024.1" `
    "AzureClientOptions:EnableAutoUpdate=true" `
    "AzureClientOptions:AzEnabled=false" `
    "AzureClientOptions:WorkSpaceName=$workspaceName" `
    "AzureClientOptions:WorkSpaceRegion=$location"

az functionapp start --name $functionAppName --resource-group $resourceGroup

# get the function app keys for scheduled and autostop functions

$scheduledFunctionKey = $(az functionapp function keys list -g $resourceGroup -n $functionAppName --function-name Scheduled --query default --output tsv)
$autoStopFunctionKey = $(az functionapp function keys list -g $resourceGroup -n $functionAppName --function-name AutoStop --query default --output tsv) 
Write-Host "AutoStop Function Key: $autoStopFunctionKey" -ForegroundColor Yellow
Write-Host "Scheduled Function Key: $scheduledFunctionKey" -ForegroundColor Yellow

# build trigger URL for the Scheduled function
$scheduledFunctionUrl = $(az functionapp function show --name $functionAppName --resource-group $resourceGroup --function-name Scheduled --query "invokeUrlTemplate"  --output tsv)
Write-Host "Scheduled Function URL: $scheduledFunctionUrl" -ForegroundColor Yellow

$AutoStopFunctionUrl = $(az functionapp function show --name $functionAppName --resource-group $resourceGroup --function-name AutoStop --query "invokeUrlTemplate"  --output tsv)
Write-Host "AutoStop Function URL: $AutoStopFunctionUrl" -ForegroundColor Yellow


# set appsetting for logic app 

az logicapp config appsettings set `
    --name $logicAppName `
    --resource-group $resourceGroup `
    --settings `
    "AutoStop-connection-1-key=$autoStopFunctionKey" `
    "Scheduled-connection-1-key=$scheduledFunctionKey" `
    "Scheduled-connection-1-triggerUrl=$scheduledFunctionUrl" `
    "AutoStop-connection-1-triggerUrl=$AutoStopFunctionUrl" `
    "WORKFLOWS_SUBSCRIPTION_ID=$subscriptionId" `
    "WORKFLOWS_RESOURCE_GROUP_NAME=$resourceGroup" `
    "FUNCTION_APPNAME=$functionAppName" `
    "FUNCTIONAPPNAME=$functionAppName"



