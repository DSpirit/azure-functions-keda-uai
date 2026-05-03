# ──────────────────────────────────────────────────────────────────────────────
# Stage 1 – Build
# Uses the .NET 10 SDK image to restore dependencies and publish the function app.
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy project file first to take advantage of Docker layer caching.
COPY ["FunctionApp.csproj", "."]
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2 – Runtime
# Uses the official Azure Functions .NET isolated worker image for .NET 10.
# This image includes the Azure Functions host process that manages the worker.
#
# If the dotnet-isolated10.0 tag is not yet available, use dotnet-isolated9.0
# as a temporary workaround: mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated9.0
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated10.0

# AzureWebJobsScriptRoot tells the Functions host where to find function metadata.
# AzureFunctionsJobHost__Logging__Console__IsEnabled enables stdout logging inside ACA.
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true

COPY --from=build /app/publish /home/site/wwwroot
