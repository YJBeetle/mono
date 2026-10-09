# Matching native Linux Mono integration

This branch-only workflow builds the Linux x64 SGen/JIT runtime and the standard
net_4_x-linux corlib from the same repository checkout, then runs all twelve
RegistrationServices tests on those actual products. It does not use Wine or the
standalone source harness. The original repository test source is compiled alone
with the installed matching compiler. The probe requires RegistrationServices to
come from the same real corlib as System.Object and rejects a shadow implementation
or PrMarshal helper in the fixture assembly. Loaded corlib hashes must match build
products; RegisterAssembly must have a real method body. Process bitness, Unix
backend, isolated machine store and absence of all twelve private fixture keys and the category test marker after
execution are also checked. The shared category is retained in its registration state. Filtering, skipping, missing XML or wrong counts fail.

Normal autogen/configure/make/install run in an Ubuntu 24.04 disposable runner.
Configure uses --with-mcs-docs=no --disable-system-aot --without-compiler-server
--without-mcs-docs --disable-boehm, plus an isolated installation prefix. This
retains the Linux SGen engine, JIT and class library, disables the unused Boehm
engine and avoids system AOT/docs/compiler server work. No C# method is rewritten
or compiled as a shadow class. Submodules use repository-pinned commits; the
binary-reference-assemblies read URL is the Wine Mono mirror used by the existing
successful build. Tracked source changes during building are rejected.

A source identity covers the full tracked source/gitlink tree except branch-only
CI files and RegistrationServicesTest.cs (which is rebuilt every time). The cache
key also binds configure flags, compiler version and the build procedure. Cache
hits must match that provenance and product hashes; no broad restore key is used.
A successful build is cached before integration tests, permitting test-harness
repairs without rebuilding identical runtime code. Build commit/run, submodule
commits, configuration/build/install logs, compiler versions, ELF/corlib products,
hashes, original test source hashes, XML and exit codes remain in artifacts.
Registry data lives under a fresh MONO_REGISTRY_PATH below RUNNER_TEMP; HOME stays
unchanged. Only the focused fixtures are run, not the entire Mono test suite.
