using System;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;

// Local certificate probes and a self-signed loopback TLS handshake.
// Not a system trust-policy or external-service test.
// Raw calls vary ONLY the DllImport calling convention.
public static class BtlsProbe
{
    const string Library = "libmono-btls-shared";
    [DllImport(Library, EntryPoint="mono_btls_x509_from_data", CallingConvention=CallingConvention.Cdecl)]
    static extern IntPtr ParseCdecl(IntPtr data, int length, int format);
    [DllImport(Library, EntryPoint="mono_btls_x509_from_data")]
    static extern IntPtr ParseDefault(IntPtr data, int length, int format);
    [DllImport(Library, EntryPoint="mono_btls_x509_free", CallingConvention=CallingConvention.Cdecl)]
    static extern void FreeCdecl(IntPtr certificate);
    static void Metadata()
    {
        int imports = 0, callbacks = 0;
        foreach (Type type in typeof(HttpWebRequest).Assembly.GetTypes())
        {
            if (type.Namespace != "Mono.Btls") continue;
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Static | BindingFlags.Public |
                                                          BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
            {
                var attribute = (DllImportAttribute)Attribute.GetCustomAttribute(method, typeof(DllImportAttribute));
                if (attribute == null || attribute.Value != "libmono-btls-shared") continue;
                if (attribute.CallingConvention != CallingConvention.Cdecl)
                    throw new Exception("BTLS_ABI_NOT_CDECL=" + type.FullName + "." + method.Name);
                imports++;
            }
            if (!typeof(MulticastDelegate).IsAssignableFrom(type)) continue;
            var callback = (UnmanagedFunctionPointerAttribute)Attribute.GetCustomAttribute(type, typeof(UnmanagedFunctionPointerAttribute));
            if (callback == null || callback.CallingConvention != CallingConvention.Cdecl)
                throw new Exception("Invalid BTLS callback convention: " + type.FullName);
            callbacks++;
        }
        if (imports < 180 || callbacks == 0) throw new Exception("BTLS metadata coverage missing");
        Console.WriteLine("btls-imports=" + imports + ";callbacks=" + callbacks);
    }

    static void InvalidCertificate()
    {
        try
        {
            using (var certificate = new X509Certificate2(new byte[] { 1, 2, 3, 4 })) { }
        }
        catch (System.Security.Cryptography.CryptographicException) { return; }
        throw new Exception("Invalid DER was unexpectedly accepted");
    }

    static void Properties(string data, bool pkcs12)
    {
        using (var certificate = new X509Certificate2(Convert.FromBase64String(data), ""))
        {
            if (!certificate.Subject.Contains("WineMonoBtlsProbe") ||
                !certificate.Issuer.Contains("WineMonoBtlsProbe") || certificate.GetCertHash().Length == 0 ||
                certificate.NotAfter <= certificate.NotBefore || certificate.GetPublicKey().Length == 0)
                throw new Exception("Certificate property validation failed");
            if (!pkcs12) return;
            if (!certificate.HasPrivateKey) throw new Exception("PKCS12 private key missing");
            byte[] exported = certificate.Export(X509ContentType.Pkcs12, "roundtrip");
            using (var restored = new X509Certificate2(exported, "roundtrip"))
                if (!restored.HasPrivateKey || restored.Thumbprint != certificate.Thumbprint)
                    throw new Exception("PKCS12 export round trip failed");
        }
    }

    static void Tls(string data)
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try
        {
            using (var certificate = new X509Certificate2(Convert.FromBase64String(data), ""))
            {
                Task server = Task.Run(() => {
                    using (var accepted = listener.AcceptTcpClient())
                    using (var ssl = new SslStream(accepted.GetStream(), false))
                    {
                        ssl.ReadTimeout = ssl.WriteTimeout = 10000;
                        ssl.AuthenticateAsServer(certificate, false, SslProtocols.Tls12, false);
                        if (ssl.ReadByte() != 42) throw new Exception("TLS request mismatch");
                        ssl.WriteByte(43);
                        ssl.Flush();
                    }
                });
                int validations = 0;
                using (var client = new TcpClient())
                {
                    client.Connect((IPEndPoint)listener.LocalEndpoint);
                    // Accept only this generated self-signed fixture, not arbitrary certificates.
                    using (var ssl = new SslStream(client.GetStream(), false, (sender, remote, chain, errors) => {
                        validations++;
                        return remote != null && remote.GetCertHashString() == certificate.GetCertHashString();
                    }))
                    {
                        ssl.ReadTimeout = ssl.WriteTimeout = 10000;
                        ssl.AuthenticateAsClient("WineMonoBtlsProbe", null, SslProtocols.Tls12, false);
                        if (!ssl.IsAuthenticated || !ssl.IsEncrypted || validations == 0)
                            throw new Exception("TLS authentication/callback missing");
                        ssl.WriteByte(42);
                        ssl.Flush();
                        if (ssl.ReadByte() != 43) throw new Exception("TLS response mismatch");
                    }
                }
                if (!server.Wait(10000)) throw new Exception("TLS server timed out");
            }
        }
        finally { listener.Stop(); }
    }
    static void Managed(string data, string expectedData)
    {
        Type factory = typeof(HttpWebRequest).Assembly.GetType("Mono.Net.Security.MonoTlsProviderFactory", true);
        var method = factory.GetMethod("GetProvider", BindingFlags.Static | BindingFlags.NonPublic,
                                       null, Type.EmptyTypes, null);
        if (method == null) throw new MissingMethodException("GetProvider");
        object provider = method.Invoke(null, null);
        string name = (string)provider.GetType().GetProperty("Name").GetValue(provider, null);
        Console.WriteLine("tls-provider=" + name);
        if (name != "btls") throw new Exception("BTLS provider unavailable");
        using (var certificate = new X509Certificate2(Convert.FromBase64String(data), ""))
        {
            Console.WriteLine("CERTIFICATE_CONSTRUCTOR_RETURNED");
            // Subject/OID lookup, Thumbprint and GetModuleHandle have independent
            // Windows stdcall paths. Validate raw certificate bytes instead.
            byte[] actual = certificate.GetRawCertData();
            byte[] expected = Convert.FromBase64String(expectedData);
            if (actual.Length != expected.Length) throw new Exception("Unexpected certificate size");
            for (int i = 0; i < actual.Length; ++i)
                if (actual[i] != expected[i]) throw new Exception("Unexpected certificate content");
            Console.WriteLine("certificate-raw-bytes=" + actual.Length);
        }
    }

    static void Raw(string data, bool cdecl)
    {
        byte[] bytes = Convert.FromBase64String(data);
        IntPtr buffer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, buffer, bytes.Length);
            for (int i = 0; i < 256; ++i)
            {
                IntPtr certificate = cdecl ? ParseCdecl(buffer, bytes.Length, 1)
                                          : ParseDefault(buffer, bytes.Length, 1);
                if (certificate == IntPtr.Zero) throw new Exception("Native DER parse returned null");
                FreeCdecl(certificate);
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static int Main(string[] args)
    {
        Console.WriteLine("PROBE_ENTER=" + args[0]);
        Console.WriteLine("POINTER_SIZE=" + IntPtr.Size);
        Console.WriteLine("SYSTEM_ASSEMBLY=" + typeof(HttpWebRequest).Assembly.Location);
        try
        {
            if (args[0] == "metadata") Metadata();
            else if (args[0] == "managed-invalid") InvalidCertificate();
            else if (args[0] == "managed-properties") Properties(args[1], false);
            else if (args[0] == "managed-pkcs12-export") Properties(args[1], true);
            else if (args[0] == "loopback-tls") Tls(args[1]);
            else if (args[0] == "native-cdecl" || args[0] == "native-default")
                Raw(args[1], args[0] == "native-cdecl");
            else Managed(args[1], args[2]);
            Console.WriteLine("PROBE_PASS=" + args[0]);
            return 0;
        }
        catch (Exception ex) { Console.WriteLine(ex.ToString()); return 1; }
    }
}
