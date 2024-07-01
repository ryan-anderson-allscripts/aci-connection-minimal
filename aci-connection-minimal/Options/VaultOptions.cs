using Microsoft.Identity.Client.AppConfig;

namespace AciConnectionMinimal.Options;

public class VaultOptions
{
    /// <summary>The ClientID of the managed service identity</summary>
    public string MSIClientId { get; set; } = string.Empty;
    /// <summary>The ObjectId of the managed service identity</summary>
    public string MSIObjectID { get; set; } = string.Empty;
    /// <summary>The ResourceID of the managed service identity</summary>
    public string MSIResourceID { get; set; } = string.Empty;
    /// <summary>The Azure Tenant ID</summary>
    public string TenantId { get; set; } = string.Empty;
    /// <summary>The Azure Subscription ID</summary>
    public string SubscriptionId { get; set; } = string.Empty;
    /// <summary>The name of the key vault</summary>
    public string VaultName { get; set; } = string.Empty;
    /// <summary>The resource group where the vault is stored</summary>
    public string VaultRg { get; set; } = string.Empty;
    /// <summary>The secret name for the HTTPS certificate</summary>
    public string CertSecretName { get; set; } = string.Empty;
    /// <summary>The URI address of the key vault</summary>
    public Uri VaultUri => new Uri($"https://{VaultName}.vault.azure.net/");
}
