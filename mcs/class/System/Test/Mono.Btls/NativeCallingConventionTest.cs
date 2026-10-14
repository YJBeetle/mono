using System;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using NUnit.Framework;

namespace MonoTests.Mono.Btls {
	[TestFixture]
	public class NativeCallingConventionTest {
		[Test]
		public void NativeImportsAndCallbacksUseCdecl ()
		{
			var assembly = typeof (HttpWebRequest).Assembly;
			if (assembly.GetType ("Mono.Btls.MonoBtlsObject") == null)
				Assert.Ignore ("BTLS is not enabled in this profile.");

			int imports = 0;
			int callbacks = 0;
			foreach (var type in assembly.GetTypes ()) {
				if (type.Namespace != "Mono.Btls")
					continue;
				foreach (var method in type.GetMethods (BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.DeclaredOnly)) {
					var attribute = (DllImportAttribute) Attribute.GetCustomAttribute (method, typeof (DllImportAttribute));
					if (attribute == null || attribute.Value != "libmono-btls-shared")
						continue;
					Assert.AreEqual (CallingConvention.Cdecl, attribute.CallingConvention, type.FullName + "." + method.Name);
					imports++;
				}
				if (!typeof (MulticastDelegate).IsAssignableFrom (type))
					continue;
				var callback = (UnmanagedFunctionPointerAttribute) Attribute.GetCustomAttribute (type, typeof (UnmanagedFunctionPointerAttribute));
				Assert.IsNotNull (callback, type.FullName);
				Assert.AreEqual (CallingConvention.Cdecl, callback.CallingConvention, type.FullName);
				callbacks++;
			}
			Assert.IsTrue (imports > 0, "No native BTLS imports inspected.");
			Assert.IsTrue (callbacks > 0, "No native BTLS callbacks inspected.");
		}
	}
}
