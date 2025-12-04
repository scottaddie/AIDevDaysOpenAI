# AIDevDaysOpenAI

## Prerequisites

1. Install the following software:
    - [.NET 10 SDK](https://dotnet.microsoft.com/download)
    - [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
1. Create an [Azure subscription](https://azure.microsoft.com/free/dotnet/) if you don't already have one
1. Create a [Stripe account](https://stripe.com/)

## Provision infrastructure and deploy app

1. Run the following command to authenticate:

    ```
    azd auth login
    ```

1. In a terminal, run the following commands to set environment variables. Replace the `<key>` placeholders with your own values:

    ```
    azd env set OPENAI_API_KEY "<key>"
    azd env set STRIPE_OAUTH_ACCESS_TOKEN "<key>"
    ```

1. Run `azd up` to provision your infrastructure and deploy the code to Azure in one step (or run `azd provision` then `azd deploy` to accomplish the tasks separately). Visit the service endpoints listed to see your app up-and-running.
