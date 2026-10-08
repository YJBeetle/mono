using System;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using Microsoft.Win32;

class LinuxEnvironment {
    static int Main(string[] args) {
        string corlib = typeof(object).Assembly.Location;
        Console.WriteLine("OS={0}; CLR={1}; ProcessBits={2}; mscorlib={3}",
            Environment.OSVersion, Environment.Version, IntPtr.Size * 8, corlib);
        if (Environment.OSVersion.Platform != PlatformID.Unix || IntPtr.Size != 8 ||
            Type.GetType("Mono.Runtime") == null) return 1;
        using (SHA256 hash = SHA256.Create()) {
            string actual = BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(corlib))).Replace("-", "").ToLowerInvariant();
            Console.WriteLine("LoadedCorlibSHA256={0}", actual);
            if (actual != args[0]) return 1;
        }
        object backend = typeof(RegistryKey).GetField("RegistryApi", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
        Console.WriteLine("RegistryBackend={0}; MONO_REGISTRY_PATH={1}", backend.GetType().FullName,
            Environment.GetEnvironmentVariable("MONO_REGISTRY_PATH"));
        if (backend.GetType().FullName != "Microsoft.Win32.UnixRegistryApi") return 1;
        Type handler = typeof(RegistryKey).Assembly.GetType("Microsoft.Win32.KeyHandler", true);
        string store = (string)handler.GetProperty("MachineStore", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null, null);
        Console.WriteLine("MachineStore={0}; Personal={1}", store,
            Environment.GetFolderPath(Environment.SpecialFolder.Personal));
        if (store != args[1]) return 1;
        string path = "MonoTests.RegistrationServices.PermissionProbe." + Guid.NewGuid();
        using (RegistryKey key = Registry.ClassesRoot.CreateSubKey(path)) {
            key.SetValue("probe", "write");
            key.Flush();
            if ((string)key.GetValue("probe") != "write") return 1;
        }
        Registry.ClassesRoot.DeleteSubKeyTree(path);
        return 0;
    }
}
