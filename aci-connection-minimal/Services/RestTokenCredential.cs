using AciConnectionMinimal.Options;
using Azure.Core;
using Azure.Identity;
using System.Text;
using System.Text.Json;
using System.Web;

namespace AciConnectionMinimal.Services;

public class RestTokenCredential : TokenCredential
{
    private const string DEFAULT_RESOURCE_URI = "https://management.azure.com";
    private readonly VaultOptions _options;

    private AccessToken _token;
    public AccessToken Token => _token;
    public RestTokenCredential(VaultOptions options)
    {
        _options = options;
    }
    private async Task<AccessToken?> GetMSIToken(string resourceUri = DEFAULT_RESOURCE_URI)
    {
        Console.WriteLine($"Retrieving MSI token for {resourceUri}");
        try
        {
            string encodedResource = HttpUtility.UrlEncode(resourceUri);
            string idEndpoint = Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT") ?? string.Empty;
            Console.WriteLine($"IDENTITY_ENDPOINT: {idEndpoint}");
            if (string.IsNullOrEmpty(idEndpoint))
            {
                var c = new DefaultAzureCredential(new DefaultAzureCredentialOptions()
                {
                    ManagedIdentityClientId = _options.MSIClientId,
                    TenantId = _options.TenantId
                });
                return c.GetToken(new TokenRequestContext([resourceUri]));
            }

            // [System.DateTimeOffset]::FromUnixTimeSeconds($tokenResponse.expires_on).datetime
            string tokenAuthUri = $"{idEndpoint}&resource={encodedResource}&principalId={_options.MSIObjectID}";
            Console.WriteLine($"tokenAuthUri: {tokenAuthUri}");
            HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, tokenAuthUri);
            request.Headers.Add("secret", Environment.GetEnvironmentVariable("IDENTITY_HEADER"));

            var httpClient = new HttpClient();

            Console.WriteLine("Sending token request to IDENTITY_ENDPOINT");
            var response = httpClient.Send(request);

            Console.WriteLine($"HTTP Response Code: {(int)response.StatusCode}:{response.StatusCode} / Success? {response.IsSuccessStatusCode}");
            Dictionary<string, string?>? tokenValues = new();
            if (response.IsSuccessStatusCode)
            {
                using (Stream responseStream = await response.Content.ReadAsStreamAsync())
                {
                    Console.WriteLine("Converting response stream to dictionary");
                    tokenValues = await JsonSerializer.DeserializeAsync<Dictionary<string, string?>>(responseStream);
                    if (tokenValues is not null)
                    {
                        Console.WriteLine($"Token Keys: {string.Join(", ", tokenValues.Keys)}");
                        Console.WriteLine($"expires_on value: {tokenValues["expires_on"]}");

                        long expireSeconds = long.Parse(tokenValues["expires_on"] ?? "0");
                        AccessToken token = new AccessToken(tokenValues["access_token"]!,
                            DateTimeOffset.FromUnixTimeSeconds(expireSeconds).DateTime);

                        Console.WriteLine($"Token expiration: {token.ExpiresOn.ToString("u")}");
                        return token;
                    }
                    else
                    {
                        Console.WriteLine(">>ERROR<< Unable to convert response to Dictionary<string, string?>");
                    }
                    return null;
                }
            }
            else
            {
                Console.WriteLine(">>ERROR<< Unable to retrieve MSI token from IDENTITY_ENDPOINT");
                Console.WriteLine(response.Content.ReadAsStringAsync().Result);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine(">>>> Exception Caught <<<<");
            var sb = new StringBuilder()
                .AppendLine(ex.GetType().Name)
                .AppendLine(ex.Message)
                .AppendLine(ex.StackTrace);
            Console.WriteLine(sb.ToString());
        }
        return null;
    }
    public async override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken)
    {
        string resourceUri = requestContext.Scopes.FirstOrDefault() ?? DEFAULT_RESOURCE_URI;
        resourceUri = resourceUri.Replace(".default", "");
        Console.WriteLine("Retrieving access token for {0}", resourceUri);
        var token = await GetMSIToken(resourceUri) ?? new();
        return token;
    }

    public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken)
    {
        return GetTokenAsync(requestContext, cancellationToken).GetAwaiter().GetResult();
    }
}
