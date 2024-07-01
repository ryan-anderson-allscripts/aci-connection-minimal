using AciConnectionMinimal.Components;
using AciConnectionMinimal.Options;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Security.KeyVault.Certificates;
using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Microsoft.AspNetCore.DataProtection.AuthenticatedEncryption.ConfigurationModel;
using Microsoft.AspNetCore.DataProtection;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using AciConnectionMinimal.Services;
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

builder.Services.AddOptions<VaultOptions>().Bind(builder.Configuration.GetSection("Vault"));
builder.Services.AddSingleton<AzureRestService>();

try
{
#pragma warning disable ASP0000 // Do not call 'IServiceCollection.BuildServiceProvider' in 'ConfigureServices'
    using (var tmpServices = builder.Services.BuildServiceProvider())
    {
        //var restSvc = tmpServices.GetRequiredService<AzureRestService>();
        //string certName = builder.Configuration.GetValue<string>("Vault:CertSecretName") ?? "";
        //X509Certificate2 x509Cert = restSvc.GetCertificate(certName);
        //Console.WriteLine(">>>> [X509Certificate2] created for {0}", x509Cert.Subject ?? "<unknown>");

        builder.Services.AddDataProtection()
            .UseCryptographicAlgorithms(new AuthenticatedEncryptorConfiguration()
            {
                EncryptionAlgorithm = Microsoft.AspNetCore.DataProtection.AuthenticatedEncryption.EncryptionAlgorithm.AES_256_CBC,
                ValidationAlgorithm = Microsoft.AspNetCore.DataProtection.AuthenticatedEncryption.ValidationAlgorithm.HMACSHA256
            });
        Console.WriteLine(">>>> Data Protection configured");

        builder.WebHost.ConfigureKestrel((context, serverOptions) =>
        {
            Console.WriteLine(">>>> Configuring Kestrel options");
            int httpPort = 8080;
            int httpsPort = 8081;
            serverOptions.ListenAnyIP(httpPort);
            Console.WriteLine(">>>>>>>> Endpoint configured for http://*:{0}", httpPort);
            //serverOptions.ListenAnyIP(httpsPort, listenOptions =>
            //{
            //    listenOptions.UseHttps(x509Cert);
            //});
            //Console.WriteLine(">>>>>>>> Endpoint configured for https://*:{0}", httpsPort);
        });
    }
#pragma warning restore ASP0000 // Do not call 'IServiceCollection.BuildServiceProvider' in 'ConfigureServices'
}
catch (Exception ex)
{
    var sb = new StringBuilder()
        .AppendLine(string.Format("[timestamp: {0:yyyy/mm/dd HH:mm:ss}]", DateTime.Now))
        .AppendLine("Exception configuring Azure services for HTTPS")
        .AppendLine(ex.GetType().FullName)
        .AppendLine(ex.Message);
    Console.WriteLine(sb.ToString());
}

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
}

app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
