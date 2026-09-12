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

using System;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.InteropServices;
using Microsoft.Win32;

using NUnit.Framework;

namespace MonoTests.System.Runtime.InteropServices {

	[TestFixture]
	public class RegistrationServicesTest {
		const string ClassId = "{5E4466A3-2BA4-414E-B70B-317D91BE57CC}";
		const string ProgId = "MonoTests.RegistrationServices.TestObject";

		static int registerCallbackCount;
		static int unregisterCallbackCount;
		static Type callbackType;

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
			registerCallbackCount = 0;
			unregisterCallbackCount = 0;
			callbackType = null;
			RemoveTestKeys ();
		}

		[TearDown]
		public void TearDown ()
		{
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
			Type type = CreateTestType ();
			RegistrationServices services = new RegistrationServices ();

			Assert.IsTrue (services.RegisterAssembly (type.Assembly, AssemblyRegistrationFlags.None), "register");
			Assert.AreEqual (1, registerCallbackCount, "register callback count");
			Assert.AreEqual (type, callbackType, "register callback type");

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
				Assert.AreEqual (type.Assembly.FullName, serverKey.GetValue ("Assembly"), "assembly");
				Assert.AreEqual (type.Assembly.ImageRuntimeVersion, serverKey.GetValue ("RuntimeVersion"), "runtime version");
			}

			Assert.IsTrue (services.UnregisterAssembly (type.Assembly), "unregister");
			Assert.AreEqual (1, unregisterCallbackCount, "unregister callback count");
			Assert.AreEqual (type, callbackType, "unregister callback type");
			Assert.IsNull (Registry.ClassesRoot.OpenSubKey (ProgId), "removed ProgID");
			Assert.IsNull (Registry.ClassesRoot.OpenSubKey ("CLSID\\" + ClassId), "removed CLSID");
		}

		public static void RegistrationCallback (Type type)
		{
			registerCallbackCount++;
			callbackType = type;
		}

		public static void UnregistrationCallback (Type type)
		{
			unregisterCallbackCount++;
			callbackType = type;
		}

		static Type CreateTestType ()
		{
			AssemblyName name = new AssemblyName ("MonoTests.RegistrationServices.DynamicAssembly");
			AssemblyBuilder assembly = AppDomain.CurrentDomain.DefineDynamicAssembly (name, AssemblyBuilderAccess.Run);
			ModuleBuilder module = assembly.DefineDynamicModule (name.Name);
			TypeBuilder type = module.DefineType ("MonoTests.RegistrationServices.DynamicTestObject",
				TypeAttributes.Class | TypeAttributes.Public);
			type.DefineDefaultConstructor (MethodAttributes.Public);
			SetAttribute (type, typeof (ComVisibleAttribute), new Type[] { typeof (bool) }, new object[] { true });
			SetAttribute (type, typeof (GuidAttribute), new Type[] { typeof (string) }, new object[] { ClassId });
			SetAttribute (type, typeof (ProgIdAttribute), new Type[] { typeof (string) }, new object[] { ProgId });
			DefineCallback (type, "Register", typeof (ComRegisterFunctionAttribute), "RegistrationCallback");
			DefineCallback (type, "Unregister", typeof (ComUnregisterFunctionAttribute), "UnregistrationCallback");
			return type.CreateType ();
		}

		static void SetAttribute (TypeBuilder type, Type attributeType, Type[] parameterTypes, object[] arguments)
		{
			type.SetCustomAttribute (new CustomAttributeBuilder (attributeType.GetConstructor (parameterTypes), arguments));
		}

		static void DefineCallback (TypeBuilder type, string name, Type attributeType, string targetName)
		{
			MethodBuilder method = type.DefineMethod (name, MethodAttributes.Public | MethodAttributes.Static,
				typeof (void), new Type[] { typeof (Type) });
			method.SetCustomAttribute (new CustomAttributeBuilder (attributeType.GetConstructor (Type.EmptyTypes), new object[0]));
			ILGenerator generator = method.GetILGenerator ();
			generator.Emit (OpCodes.Ldarg_0);
			generator.Emit (OpCodes.Call, typeof (RegistrationServicesTest).GetMethod (targetName,
				BindingFlags.Public | BindingFlags.Static));
			generator.Emit (OpCodes.Ret);
		}

		static void RemoveTestKeys ()
		{
			Registry.ClassesRoot.DeleteSubKeyTree (ProgId, false);
			Registry.ClassesRoot.DeleteSubKeyTree ("CLSID\\" + ClassId, false);
		}
	}
}
