FROM mcr.microsoft.com/dotnet/aspnet:8.0.6 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
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
RUN <<EOF
  apt-get update
  # Install pre-requisite packages.
  apt-get install -y wget
  # Download the PowerShell package file
  wget https://github.com/PowerShell/PowerShell/releases/download/v7.4.3/powershell_7.4.3-1.deb_amd64.deb
  # Install the PowerShell package
  dpkg -i powershell_7.4.3-1.deb_amd64.deb
  # Resolve missing dependencies and finish the install (if necessary)
  apt-get install -f
  # Delete the downloaded package file
  rm powershell_7.4.3-1.deb_amd64.deb
EOF
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "aci-connection-minimal.dll"]