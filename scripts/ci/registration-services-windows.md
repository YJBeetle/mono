# Windows compatibility and candidate Mono regression harness

This branch-only workflow compiles the repository's `RegistrationServicesTest.cs`
with native .NET Framework `csc.exe`, then runs its two fixtures serially using
official NUnit and NUnit.Runners 2.6.4 packages from NuGet. The six helper assembly
targets, version directories, compilation defines and PIA signing key mirror
`mcs/class/corlib/Makefile`. The native jobs use the Windows runner's .NET Framework.
The Mono jobs use a previously built candidate corlib containing the PR's implementation,
with the same Wine Mono 11.3.0 engine/library bundle used by its original build workflow.
This is focused testing, not a complete corlib build or a new Mono runtime build.

Each x86/x64 matrix job uses a separate disposable `windows-2022` runner. A compiled
probe verifies the requested runtime, process bitness and write access to a temporary HKCR key.
The NUnit console runner and test assemblies target the requested architecture.
Registry tests run serially. Native jobs exclude
`NotOnWindows,NotWorking,CAS,UI,NotDotNet`; Mono jobs exclude only
`NotOnWindows,NotWorking,CAS,UI`. There are 12 defined tests: two type tests and ten
registry tests. Native jobs select nine and filter out three Mono-specific tests;
Mono jobs select all twelve, including both new generic exception assertions and
all three Mono safeguards. Counts distinguish filtering from runtime skips.
Unexpected test counts, ignored/skipped tests,
zero-test results, missing XML, build failures and NUnit failures all fail the job.
The original NUnit exit codes remain in the artifacts.

Artifacts are uploaded on success or failure and retained for 30 days. They include
console/transcript logs, NUnit XML, counts, exit codes, source commit and SHA-256
hashes, Windows/.NET/compiler versions, the executed probe and process bitness,
package hashes and compiled fixtures. Mono artifacts also include candidate provenance,
engine/corlib hashes and the SHA-256 of the corlib actually loaded by the Mono process.
NUnit is kept in that process with `/framework:mono-4.0 /process:Single`.
NUnit's native XML environment describes its CLR 2 launcher; native execution is
explicitly selected as `net-4.0`, and the separate probe records CLR 4 and bitness.
Baseline PIA registration can leave a TypeLib
key; the runner must remain disposable. This harness does not prove COM activation,
native ACL edge cases, or untested value-type and COM-imported registration paths.

The candidate `registration-services-candidate/mscorlib.dll` is copied unchanged
from artifact 10689060521 of successful run 35711383323. Its pinned workflow asserts
the Mono gitlink is `56fe1db32314946a3be29b07771879260629b67f` before building it.
`provenance.json` records that source, the artifact hash and official runtime archive
hash. The binary is kept only on this test branch to avoid cross-repository credentials;
it is not intended for the PR. A small Visual C++ host loads the existing x86/x64 DLL,
sets its library/config directories and calls the exported `mono_main`. It builds
only this launcher, not Mono. The runtime archive and extracted bundle are temporary
runner files and are not uploaded again as test artifacts.
The archive SHA is verified before extraction. The runner's existing Python extracts
the engine, 4.5 libraries, GAC, helper DLLs and config only, copying archive symlink
targets as identical regular files to avoid Windows tar/symlink problems. Reference
API profiles, build tools and unrelated framework support files are not needed.

Only pushes to `codex/registration-services-windows-ci` in `YJBeetle/mono` run this
workflow. It requests `contents: read`, has no secrets or submodules, and pins the
official checkout/upload actions by commit. It does not publish comments or PRs.

Native Linux integration now uses the separate matching-source workflow described in
`registration-services-linux-matching.md`. Commits marked [matching-linux] skip the
historical source-level fallback job in this workflow. That fallback and its previous
results are not substitutes for the matching runtime/corlib run.

The reviewer-requested simplification removes both snapshot helper types and their
two tests. Fixture setup seeds the shared category directly. Cleanup removes only
its test marker and the fixture-owned ProgID/CLSID/callback keys, leaving the shared
category in the state produced by registration. The post-test probe verifies those
private keys and marker are absent without deleting shared category content.
