//
// RegistrationServicesTest.cs - NUnit tests for RegistrationServices
//
// Copyright 2026 YJBeetle
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#if !MOBILE

using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;

using NUnit.Framework;

namespace MonoTests.System.Runtime.InteropServices {

	[TestFixture]
	public class RegistrationServicesTest {
		const string ClassId = "{5E4466A3-2BA4-414E-B70B-317D91BE57CC}";
		const string ProgId = "MonoTests.RegistrationServices.TestObject";
		const string DerivedClassId = "{641D963E-EA94-4E4F-B6EF-1DFEB43FB697}";
		const string DerivedProgId = "MonoTests.RegistrationServices.DerivedTestObject";
		const string CallbackPath = "MonoTests.RegistrationServices.CallbackState";

		[ComVisible (true)]
		public class VisibleClass {
			public VisibleClass ()
			{
			}
		}

		[ComVisible (true)]
		public abstract class AbstractClass {
		}

		[ComVisible (true)]
		public class ClassWithoutPublicConstructor {
			ClassWithoutPublicConstructor ()
			{
			}
		}

		[ComVisible (false)]
		public class InvisibleClass {
			public InvisibleClass ()
			{
			}
		}

		[SetUp]
		public void SetUp ()
		{
			if (Environment.OSVersion.Platform != PlatformID.Win32NT)
				Assert.Ignore ("COM registration is only supported on Windows.");
			RemoveTestKeys ();
		}

		[TearDown]
		public void TearDown ()
		{
			if (Environment.OSVersion.Platform == PlatformID.Win32NT)
				RemoveTestKeys ();
		}

		[Test]
		public void TypeRequiresRegistration ()
		{
			RegistrationServices services = new RegistrationServices ();
			Assert.IsTrue (services.TypeRequiresRegistration (typeof (VisibleClass)), "visible");
			Assert.IsFalse (services.TypeRequiresRegistration (typeof (AbstractClass)), "abstract");
			Assert.IsFalse (services.TypeRequiresRegistration (typeof (ClassWithoutPublicConstructor)), "constructor");
			Assert.IsFalse (services.TypeRequiresRegistration (typeof (InvisibleClass)), "invisible");
			Assert.IsFalse (services.TypeRequiresRegistration (typeof (IDisposable)), "interface");
		}

		[Test]
		public void RegisterAndUnregisterAssembly ()
		{
			string path = Path.Combine (AppDomain.CurrentDomain.BaseDirectory,
				"RegistrationServicesTestAssembly.dll");
			Assembly assembly = Assembly.LoadFrom (path);
			Type type = assembly.GetType ("MonoTests.RegistrationServices.TestObject", true);
			RegistrationServices services = new RegistrationServices ();

			Assert.IsTrue (services.RegisterAssembly (assembly, AssemblyRegistrationFlags.None), "register");

			using (RegistryKey progIdKey = Registry.ClassesRoot.OpenSubKey (ProgId)) {
				Assert.IsNotNull (progIdKey, "ProgID key");
				Assert.AreEqual (type.FullName, progIdKey.GetValue (String.Empty), "ProgID description");
				using (RegistryKey classIdKey = progIdKey.OpenSubKey ("CLSID"))
					Assert.AreEqual (ClassId, classIdKey.GetValue (String.Empty), "ProgID CLSID");
			}

			using (RegistryKey serverKey = Registry.ClassesRoot.OpenSubKey ("CLSID\\" + ClassId + "\\InprocServer32")) {
				Assert.IsNotNull (serverKey, "InprocServer32 key");
				Assert.AreEqual ("mscoree.dll", serverKey.GetValue (String.Empty), "server");
				Assert.AreEqual ("Both", serverKey.GetValue ("ThreadingModel"), "threading model");
				Assert.AreEqual (type.FullName, serverKey.GetValue ("Class"), "class");
				Assert.AreEqual (assembly.FullName, serverKey.GetValue ("Assembly"), "assembly");
				Assert.AreEqual (assembly.ImageRuntimeVersion, serverKey.GetValue ("RuntimeVersion"), "runtime version");
			}

			using (RegistryKey callbackKey = Registry.ClassesRoot.OpenSubKey (CallbackPath)) {
				Assert.IsNotNull (callbackKey, "callback key");
				Assert.AreEqual (type.FullName, callbackKey.GetValue ("Register"), "register callback");
				Assert.AreEqual ("HKEY_CLASSES_ROOT\\CLSID\\" + DerivedClassId,
					callbackKey.GetValue ("DerivedRegister"), "derived callback overrides base callback");
			}

			Assert.IsTrue (services.UnregisterAssembly (assembly), "unregister");
			Assert.IsNull (Registry.ClassesRoot.OpenSubKey (ProgId), "removed ProgID");
			Assert.IsNull (Registry.ClassesRoot.OpenSubKey ("CLSID\\" + ClassId), "removed CLSID");
			Assert.IsNull (Registry.ClassesRoot.OpenSubKey (DerivedProgId), "removed derived ProgID");
			Assert.IsNull (Registry.ClassesRoot.OpenSubKey ("CLSID\\" + DerivedClassId), "removed derived CLSID");
			using (RegistryKey callbackKey = Registry.ClassesRoot.OpenSubKey (CallbackPath)) {
				Assert.IsNotNull (callbackKey, "callback key after unregister");
				Assert.AreEqual (type.FullName, callbackKey.GetValue ("Unregister"), "unregister callback");
				Assert.AreEqual ("HKEY_CLASSES_ROOT\\CLSID\\" + DerivedClassId,
					callbackKey.GetValue ("DerivedUnregister"), "derived unregister callback overrides base callback");
			}
		}

		static void RemoveTestKeys ()
		{
			Registry.ClassesRoot.DeleteSubKeyTree (ProgId, false);
			Registry.ClassesRoot.DeleteSubKeyTree ("CLSID\\" + ClassId, false);
			Registry.ClassesRoot.DeleteSubKeyTree (DerivedProgId, false);
			Registry.ClassesRoot.DeleteSubKeyTree ("CLSID\\" + DerivedClassId, false);
			Registry.ClassesRoot.DeleteSubKeyTree (CallbackPath, false);
		}
	}
}

#endif
