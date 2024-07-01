FROM mcr.microsoft.com/dotnet/aspnet:8.0-windowsservercore-ltsc2019 AS base
#FROM mcr.microsoft.com/dotnet/aspnet:8.0-nanoserver-1809 AS base
SHELL ["powershell.exe", "-Command"]
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2019 AS build
WORKDIR /src
COPY ["aci-connection-minimal.csproj", "."]
RUN dotnet restore "./aci-connection-minimal.csproj"
COPY . .
WORKDIR "/src/."
RUN dotnet build "aci-connection-minimal.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "aci-connection-minimal.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
## Install custom tooling - Azure CLI & PowerShell 7
COPY ["AzureCLI.msi", "."]
COPY ["PowerShell7.msi", "."]
RUN Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi'
RUN Start-Process msiexec.exe -Wait -ArgumentList '/package PowerShell7.msi /quiet ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1'
## End install custom tooling
COPY --from=publish /app/publish .
ENV ASPNETCORE_HTTP_PORTS=8080
ENV ASPNETCORE_HTTPS_PORTS=8081
ENTRYPOINT ["dotnet", "aci-connection-minimal.dll"]