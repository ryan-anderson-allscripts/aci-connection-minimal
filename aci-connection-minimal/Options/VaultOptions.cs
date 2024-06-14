using Microsoft.Identity.Client.AppConfig;

namespace AciConnectionMinimal.Options;

public class VaultOptions
{
    public string ManagedIdentityId { get; set; } = string.Empty;
    public string TenantId { get; set; } = string.Empty;
    public string VaultName { get; set; } = string.Empty;
    public string VaultRg { get; set; } = string.Empty;
    public string SubscriptionId { get; set; } = string.Empty;
}
