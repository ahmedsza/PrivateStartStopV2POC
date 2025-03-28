# Start/Stop V2 Solution with Private Networking

IMPORTANT NOTE: This is a POC and not intended for production use. 


This is a POC based on https://learn.microsoft.com/en-us/azure/azure-functions/start-stop-vms/overview where it is converted to use private networking 
Refer to the article for more details 

The first half requires creating the logic app and function app manually. This will also create all associated dependencies including storage, app insights and private endpoints



The second half is the script to configure the resources.

# Manual Configuration Script for Start/Stop V2 Solution

This document explains the PowerShell script (`manualconfigv2.ps1`) used to configure the Start/Stop V2 solution components.


## Prerequisites

- Azure CLI installed
- Active Azure subscription
- Access to a machine with line of sight to Azure resources
- The following resources must be manually deployed first:
    - Resource Group
    - VNet with 3 subnets (private endpoint, VNet integration, VM testing)
    - Logic App with private endpoint and VNet integration
    - Function App with private endpoint and VNet integration
    - Storage accounts for both Logic App and Function App (these are created as part of the manual deployment)
    - Recommend to use seperate storage accounts for Logic App and Function App
    - App Insights - created as part od the manual deployment. Can use just one instance

## Script Overview

The script performs the following key operations:

1. **Storage Account Configuration**
     - Creates required queues:
         - create-alert-request
         - orchestration-request
         - execution-request
         - savings-request-queue
         - auto-update-request-queue
     - Creates required tables:
         - requeststoretable
         - subscriptionrequeststoretable
         - autoupdaterequestdetailsstoretable

2. **Identity Configuration**
     - Assigns managed identities to both Function App and Logic App
     - Grants Contributor access to the Function App at subscription level

3. **Application Deployment**
     - Deploys `StartStopV2.zip` to Function App
     - Deploys `lav2.zip` to Logic App

4. **Application Settings**
     - Configures Function App settings including:
         - Azure client options
         - Storage options
         - Centralized logging options
         - Auto-update settings
     - Sets up Logic App connection settings and trigger URLs

## Usage

1. Update the variables section with your resource names
2. Run the script in parts preferably in PowerShell
3. Monitor the console output for any errors

## Important Notes

- All resource names must match exactly with manually deployed resources
- Script requires appropriate Azure permissions
- Custom role assignment recommended instead of Contributor role
- Keep track of generated keys and URLs for troubleshooting

## Testing
Open the workflows in Logic Apps. Make the resources you are targetting is correct set. Check https://learn.microsoft.com/en-us/azure/azure-functions/start-stop-vms/deploy for more details especially regarding RequestScopes. 