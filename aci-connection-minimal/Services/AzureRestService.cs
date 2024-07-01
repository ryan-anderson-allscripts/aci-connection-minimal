using Azure.Security.KeyVault.Secrets;
using Azure.Security.KeyVault.Certificates;
using AciConnectionMinimal.Options;
using Microsoft.Extensions.Options;
using Microsoft.Identity.Client;
using System.Security.Cryptography.X509Certificates;
using System.Diagnostics;
using Azure;
using System.Text;
using Microsoft.Extensions.Logging;
using Azure.Identity;
using Azure.Core;

namespace AciConnectionMinimal.Services;

public class AzureRestService
{
    private readonly VaultOptions _options;
    private readonly ILogger<AzureRestService> _logger;
    private const string DEFAULT_RESOURCE_URI = "https://management.azure.com";
    private RestTokenCredential? _credential;
    public RestTokenCredential CurrentCredential => GetCredential();

    public AzureRestService(IOptionsMonitor<VaultOptions> options, ILogger<AzureRestService> logger)
    {
        _options = options.CurrentValue;
        _logger = logger;
    }
    private RestTokenCredential GetCredential()
    {
        if (_credential is null || _credential.Token.ExpiresOn <= DateTime.Now)
        {
            _logger.LogDebug("Generating new access token");
            _credential = new RestTokenCredential(_options);
        }
        _logger.LogDebug("Token expiration: {exp}", _credential.Token.ExpiresOn.ToString("u"));
        return _credential;
    }

    public X509Certificate2 GetCertificate(string certName, string? vaultName = null)
    {
        vaultName ??= _options.VaultName;
        _logger.LogDebug("Retrieving certificate {0} from {1}", certName, vaultName);
        /*
        var credentialOpts = new DefaultAzureCredentialOptions()
        {
            ManagedIdentityResourceId = new ResourceIdentifier(_options.MSIResourceID),
            TenantId = _options.TenantId
        };
        var vaultCred = new DefaultAzureCredential(credentialOpts);
        CertificateClient client = new(_options.VaultUri, vaultCred);
        */
        CertificateClient client = new(_options.VaultUri, CurrentCredential);
        return client.DownloadCertificate(certName);
    }
}

/*
# ======= POWERSHELL =======
$settings = (Get-Content .\appsettings.json|ConvertFrom-Json)
[string]$CLIENT_ID = $settings.Vault.MSIClientID
[string]$PRINCIPAL_ID = $settings.Vault.MSIObjectID

$resourceURI = "https%3A%2F%2Fmanagement.azure.com"
$resourceURI = "https%3A%2F%2Fvault.azure.net"
$tokenAuthURI = "${env:IDENTITY_ENDPOINT}&resource=$resourceURI&principalId=$PRINCIPAL_ID"
$tokenAuthURI = "${env:IDENTITY_ENDPOINT}&resource=$resourceURI&clientId=$CLIENT_ID"
$tokenResponse = Invoke-RestMethod -Method Get -Headers @{"secret"="$env:IDENTITY_HEADER"} -Uri $tokenAuthUri
$TOKEN = $tokenResponse.access_token

[string]$VAULT_NAME = 'op5-0-aks-kv'
$VAULT_URI = "https://$VAULT_NAME.vault.azure.net/secrets?api-version=7.4"
$SECRET_NAME = "op5containerrgadmin"
$vaultResponse = Invoke-RestMethod -Method Get -Headers @{"Authorization"="Bearer $TOKEN"} -Uri $VAULT_URI
$secretResponse = Invoke-RestMethod -Method Get -Headers @{"Authorization"="Bearer $TOKEN"} -Uri "https://$VAULT_NAME.vault.azure.net/secrets/$SECRET_NAME?api-version=7.4"


// ======= ASP.NET =======
string kvName = builder.Configuration.GetValue<string>("Vault:VaultName") ?? string.Empty;
string secretName = builder.Configuration.GetValue<string>("Vault:CertSecretName") ?? string.Empty;
string managedRID = builder.Configuration.GetValue<string>("Vault:MSIResourceID") ?? string.Empty;
string managedCID = builder.Configuration.GetValue<string>("Vault:MSIClientID") ?? string.Empty;
string managedOID = builder.Configuration.GetValue<string>("Vault:MSIObjectID") ?? string.Empty;
string tenantId = builder.Configuration.GetValue<string>("Vault:TenantID") ?? string.Empty;
_logger.LogInformation(@"
=== VAULT SETTINGS ===
Vault: {0}
Secret: {1}
MSI: {2}
MSI Client: {3}
MSI ObjectID {4}
Tenant Id: {5}", kvName, secretName, managedRID, managedCID, managedOID, tenantId);

try
{
    var msiRid = new Azure.Core.ResourceIdentifier(managedRID);
    _logger.LogInformation(@"Resource:
    SubscriptionID: {0}
    ResourceGroup:  {1}
    Name:           {2}
    ResourceType:   {3}
    [timestamp: {4:yyyy/mm/dd HH:mm:ss}]
", msiRid.SubscriptionId, msiRid.ResourceGroupName, msiRid.Name, msiRid.ResourceType, DateTime.Now);

    var credentialOpts = new DefaultAzureCredentialOptions()
    {
        ManagedIdentityResourceId = msiRid,
        //ManagedIdentityClientId = managedOID,
        TenantId = tenantId
    };
    var vaultCred = new DefaultAzureCredential(credentialOpts);
    Uri vaultUri = new Uri($"https://{kvName}.vault.azure.net/");

    //builder.Configuration.AddAzureKeyVault(vaultUri, vaultCred);

    _logger.LogInformation(">>>>>>>> testing cert retrieval");
    var certClient = new CertificateClient(vaultUri, vaultCred);
    var certResult = certClient.GetCertificate(secretName).Value;
    _logger.LogInformation("(>>>>>>>>>>>> cert length: {0}", certResult.Cer.Length);

    using (var tmpApp = builder.Build())
    {

    }

    var kvClient = new SecretClient(vaultUri, vaultCred);

    _logger.LogInformation(">>>>>>>> testing secret list retrieval");
    var secrets = kvClient.GetPropertiesOfSecrets().ToList();

    _logger.LogInformation(">>>>>>>> testing secret retrieval");
    var secret = kvClient.GetSecret(secretName).Value;
 
 */