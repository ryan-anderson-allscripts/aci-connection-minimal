FROM mcr.microsoft.com/dotnet/aspnet:8.0-windowsservercore-ltsc2022 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022 AS build
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
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "aci-connection-minimal.dll"]