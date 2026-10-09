using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Microsoft.Win32;

class MatchingLinuxEnvironment {
    static int Main(string[] args) {
        string corlib = typeof(object).Assembly.Location;
        Console.WriteLine("OS={0}; CLR={1}; ProcessBits={2}; mscorlib={3}",
            Environment.OSVersion, Environment.Version, IntPtr.Size * 8, corlib);
        if (Environment.OSVersion.Platform != PlatformID.Unix || IntPtr.Size != 8 || Type.GetType("Mono.Runtime") == null) return 1;
        if (!Path.GetFullPath(corlib).StartsWith(Path.GetFullPath(args[2]) + Path.DirectorySeparatorChar, StringComparison.Ordinal)) return 1;
        using (SHA256 hash = SHA256.Create()) {
            string actual = BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(corlib))).Replace("-", "").ToLowerInvariant();
            Console.WriteLine("LoadedCorlibSHA256={0}", actual);
            if (actual != args[0]) return 1;
        }
        Console.WriteLine("RegistrationServicesImplementationAssembly={0}", typeof(RegistrationServices).Assembly.Location);
        if (typeof(RegistrationServices).Assembly != typeof(object).Assembly) return 1;
        Assembly tests = Assembly.LoadFrom(args[3]);
        if (tests.GetType("System.Runtime.InteropServices.RegistrationServices") != null || tests.GetType("System.Runtime.InteropServices.PrMarshal") != null) return 1;
        byte[] method = typeof(RegistrationServices).GetMethod("RegisterAssembly").GetMethodBody().GetILAsByteArray();
        Console.WriteLine("RegisterAssemblyILBytes={0}; TestAssembly={1}; ValidationMode=matching engine and real corlib", method.Length, tests.Location);
        if (method.Length < 100) return 1;
        object backend = typeof(RegistryKey).GetField("RegistryApi", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
        Console.WriteLine("RegistryBackend={0}", backend.GetType().FullName);
        if (backend.GetType().FullName != "Microsoft.Win32.UnixRegistryApi") return 1;
        Type handler = typeof(RegistryKey).Assembly.GetType("Microsoft.Win32.KeyHandler", true);
        string store = (string)handler.GetProperty("MachineStore", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null, null);
        Console.WriteLine("MachineStore={0}; Personal={1}", store, Environment.GetFolderPath(Environment.SpecialFolder.Personal));
        if (store != args[1]) return 1;
        if (args.Length > 4) {
            string[] paths = {
                "MonoTests.RegistrationServices.TestObject", "CLSID\\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}",
                "MonoTests.RegistrationServices.DerivedTestObject", "CLSID\\{641D963E-EA94-4E4F-B6EF-1DFEB43FB697}",
                "CLSID\\{F0439499-B07C-4FA5-BC3B-8402B70B3AFF}", "MonoTests.RegistrationServices.CallbackState",
                "MonoTests.RegistrationServices.VersionedObject", "CLSID\\{5C9782F8-3BAA-42C7-A461-B8C94F2FA438}",
                "MonoTests.RegistrationServices.InvalidCallbackObject", "CLSID\\{F81E4AE1-917F-43C8-BD29-A56B182287AA}",
                "MonoTests.RegistrationServices.GenericCallbackObject", "CLSID\\{86F43A7E-B430-4F56-9C6C-DD61BA460217}"
            };
            foreach (string path in paths) {
                using (RegistryKey key = Registry.ClassesRoot.OpenSubKey(path)) {
                    if (key != null) { Console.Error.WriteLine("Remaining test key: {0}", path); return 1; }
                }
            }
            using (RegistryKey category = Registry.ClassesRoot.OpenSubKey("Component Categories\\{62C8FE65-4EBB-45E7-B440-6E39B2CDBF29}")) {
                if (category != null && category.GetValue("MonoRegistrationServicesTest") != null) {
                    Console.Error.WriteLine("Remaining fixture category value"); return 1;
                }
                Console.WriteLine("SharedCategoryExists={0}; SharedCategoryDescription={1}", category != null,
                    category == null ? null : category.GetValue("0"));
            }
            Console.WriteLine("CleanupVerified=True; TestKeysAbsent={0}; FixtureCategoryValueAbsent=True", paths.Length);
            return 0;
        }
        string probe = "MonoTests.RegistrationServices.PermissionProbe." + Guid.NewGuid();
        using (RegistryKey key = Registry.ClassesRoot.CreateSubKey(probe)) {
            key.SetValue("probe", "write"); key.Flush();
            if ((string)key.GetValue("probe") != "write") return 1;
        }
        Registry.ClassesRoot.DeleteSubKeyTree(probe);
        return 0;
    }
}
