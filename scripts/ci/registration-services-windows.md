# Native Windows compatibility harness

This branch-only workflow compiles the repository's `RegistrationServicesTest.cs`
with native .NET Framework `csc.exe`, then runs its two fixtures serially using
official NUnit and NUnit.Runners 2.6.4 packages from NuGet. The six helper assembly
targets, version directories, compilation defines and PIA signing key mirror
`mcs/class/corlib/Makefile`. It uses the Windows runner's native mscorlib, not the
implementation being added to Mono. This is focused native compatibility evidence,
not a complete corlib build or verification of Mono's implementation.

Each x86/x64 matrix job uses a separate disposable `windows-2022` runner. A compiled
probe verifies native CLR, process bitness and write access to a temporary HKCR key.
The NUnit console runner and test assemblies target the requested architecture.
Registry tests run serially and excluded categories are
`NotOnWindows,NotWorking,CAS,UI,NotDotNet`. Unexpected ignored/skipped tests,
zero-test results, missing XML, build failures and NUnit failures all fail the job.
The original NUnit exit codes remain in the artifacts.

Artifacts are uploaded on success or failure and retained for 30 days. They include
console/transcript logs, NUnit XML, counts, exit codes, source commit and SHA-256
hashes, Windows/.NET/compiler versions, the executed probe and process bitness,
package hashes and compiled fixtures. Baseline PIA registration can leave a TypeLib
key; the runner must remain disposable. This harness does not prove COM activation,
native ACL edge cases, or Mono-specific preflight rejection and diagnostics.

Only pushes to `codex/registration-services-windows-ci` in `YJBeetle/mono` run this
workflow. It requests `contents: read`, has no secrets or submodules, and pins the
official checkout/upload actions by commit. It does not publish comments or PRs.
