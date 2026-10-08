param(
    [Parameter(Mandatory = $true)][ValidateSet('x86', 'x64')][string]$Architecture,
    [ValidateSet('native', 'mono')][string]$Runtime = 'native'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $repo "artifacts/registration-services-$Runtime-$Architecture"
$build = Join-Path $output 'build'
$packages = Join-Path $output 'packages'
New-Item -ItemType Directory -Force $build, $packages | Out-Null
Start-Transcript -Path (Join-Path $output 'harness.log')
$exitCode = 1
try {
    $frameworkDirectory = if ($Architecture -eq 'x86') { 'Framework' } else { 'Framework64' }
    $csc = Join-Path $env:WINDIR "Microsoft.NET/$frameworkDirectory/v4.0.30319/csc.exe"
    if (!(Test-Path $csc)) { throw "Framework compiler missing: $csc" }
    $source = Join-Path $repo 'mcs/class/corlib/Test/System.Runtime.InteropServices'
    $manifest = @{
        commit = (& git -C $repo rev-parse HEAD)
        architecture = $Architecture
        runtime = $Runtime
        os = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture)
        framework = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' | Select-Object Release, Version)
        compiler = $csc
        compilerVersion = (Get-Item $csc).VersionInfo.FileVersion
        scope = 'Focused repository tests on the selected runtime; not a full corlib build.'
        sources = @(Get-ChildItem "$source/RegistrationServices*.cs" | Get-FileHash -Algorithm SHA256 | Select-Object Path, Hash)
        makefile = (Get-FileHash (Join-Path $repo 'mcs/class/corlib/Makefile') -Algorithm SHA256).Hash
        signingKey = (Get-FileHash (Join-Path $repo 'mcs/class/mono.snk') -Algorithm SHA256).Hash
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output 'source-environment.json')

    foreach ($id in @('NUnit', 'NUnit.Runners')) {
        $lower = $id.ToLowerInvariant()
        $zip = Join-Path $packages "$id.2.6.4.zip"
        Invoke-WebRequest -UseBasicParsing "https://api.nuget.org/v3-flatcontainer/$lower/2.6.4/$lower.2.6.4.nupkg" -OutFile $zip
        Get-FileHash $zip -Algorithm SHA256 | Format-List
        Expand-Archive -Path $zip -DestinationPath (Join-Path $packages $id)
    }
    $nunit = (Get-ChildItem (Join-Path $packages 'NUnit') -Recurse -Filter nunit.framework.dll | Select-Object -First 1).FullName
    if (!$nunit) { throw 'NUnit framework DLL missing' }
    Copy-Item $nunit $build
    $runnerName = if ($Architecture -eq 'x86') { 'nunit-console-x86.exe' } else { 'nunit-console.exe' }
    $runner = (Get-ChildItem (Join-Path $packages 'NUnit.Runners') -Recurse -Filter $runnerName | Select-Object -First 1).FullName
    if (!$runner) { throw "NUnit runner missing: $runnerName" }

    if ($Runtime -eq 'mono') {
        # The pinned, already-built candidate avoids a new full Mono build and cross-repository credentials.
        $candidateDirectory = Join-Path $PSScriptRoot 'registration-services-candidate'
        $provenance = Get-Content (Join-Path $candidateDirectory 'provenance.json') | ConvertFrom-Json
        $candidate = Join-Path $candidateDirectory 'mscorlib.dll'
        $candidateHash = $provenance.corlibSha256
        if ((Get-FileHash $candidate -Algorithm SHA256).Hash -ne $candidateHash) { throw 'Candidate corlib hash mismatch' }
        Copy-Item (Join-Path $candidateDirectory 'provenance.json') $output
        $runtimeWork = Join-Path $env:RUNNER_TEMP "registration-services-mono-$Architecture"
        New-Item -ItemType Directory -Force $runtimeWork | Out-Null
        $archive = Join-Path $runtimeWork 'runtime.tar.xz'
        Invoke-WebRequest -UseBasicParsing $provenance.runtimeArchiveUrl -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $provenance.runtimeArchiveSha256) { throw 'Runtime archive hash mismatch' }
        & tar -xf $archive -C $runtimeWork
        if ($LASTEXITCODE -ne 0) { throw 'Runtime archive extraction failed' }
        $runtimeRoot = Join-Path $runtimeWork 'wine-mono-11.3.0'
        Copy-Item $candidate (Join-Path $runtimeRoot 'lib/mono/4.5/mscorlib.dll') -Force
        Get-FileHash (Join-Path $runtimeRoot 'bin/libmono-2.0-x86.dll'), (Join-Path $runtimeRoot 'bin/libmono-2.0-x86_64.dll'), (Join-Path $runtimeRoot 'lib/mono/4.5/mscorlib.dll') -Algorithm SHA256 |
            Select-Object Path, Hash | ConvertTo-Json | Set-Content (Join-Path $output 'loaded-runtime-hashes.json')
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (!$vs) { throw 'Visual C++ toolchain missing for the small embedding host' }
        $vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvarsall.bat'
        $vcArchitecture = if ($Architecture -eq 'x86') { 'x86' } else { 'amd64' }
        $monoHost = Join-Path $build 'mono-host.exe'
        $hostSource = Join-Path $PSScriptRoot 'registration-services-windows-host.c'
        $compileHost = Join-Path $build 'compile-host.cmd'
        @"
@echo off
call "$vcvars" $vcArchitecture
if errorlevel 1 exit /b %errorlevel%
cl.exe /nologo /W4 /TC /Fe"$monoHost" /Fo"$build/mono-host.obj" "$hostSource"
exit /b %errorlevel%
"@ | Set-Content $compileHost
        & cmd.exe /c $compileHost
        if ($LASTEXITCODE -ne 0) { throw 'Mono embedding host compilation failed' }
    }

    function Compile([string]$Name, [string]$File, [string[]]$Options = @()) {
        $target = Join-Path $build $Name
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        & $csc /nologo /target:library "/platform:$Architecture" "/out:$target" @Options (Join-Path $source $File)
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed for $Name (exit $LASTEXITCODE)" }
    }
    # Mirror the six fixture targets and defines in mcs/class/corlib/Makefile.
    Compile 'RegistrationServicesTestAssembly.dll' 'RegistrationServicesTestAssembly.cs'
    Compile 'RegistrationServicesPIATestAssembly.dll' 'RegistrationServicesTestAssembly.cs' @('/define:PRIMARY_INTEROP_ASSEMBLY', "/keyfile:$(Join-Path $repo 'mcs/class/mono.snk')")
    Compile 'RegistrationVersion1/RegistrationServicesVersionedTestAssembly.dll' 'RegistrationServicesBoundaryTestAssembly.cs' @('/define:VERSION_ONE')
    Compile 'RegistrationVersion2/RegistrationServicesVersionedTestAssembly.dll' 'RegistrationServicesBoundaryTestAssembly.cs' @('/define:VERSION_TWO')
    Compile 'RegistrationServicesInvalidCallbackTestAssembly.dll' 'RegistrationServicesBoundaryTestAssembly.cs' @('/define:INVALID_CALLBACK')
    Compile 'RegistrationServicesGenericCallbackTestAssembly.dll' 'RegistrationServicesBoundaryTestAssembly.cs' @('/define:GENERIC_CALLBACK')
    Compile 'RegistrationServices.Tests.dll' 'RegistrationServicesTest.cs' @("/reference:$nunit")

    # Run this probe in the same target architecture as the tests. Permission failures are failures, not passes.
    $probeSource = Join-Path $build 'NativeEnvironment.cs'
    @'
using System;
using System.Runtime.InteropServices;
using System.IO;
using System.Security.Cryptography;
using Microsoft.Win32;
class NativeEnvironment {
    static int Main(string[] args) {
        Console.WriteLine("OS={0}; CLR={1}; ProcessBits={2}; mscorlib={3}",
            Environment.OSVersion, Environment.Version, IntPtr.Size * 8, typeof(object).Assembly.Location);
        bool isMono = Type.GetType("Mono.Runtime") != null;
        bool expectMono = args.Length > 1 && args[1] == "mono";
        Console.WriteLine("Mono={0}", isMono);
        if (isMono != expectMono || IntPtr.Size * 8 != Int32.Parse(args[0])) return 1;
        if (isMono) {
            using (SHA256 hash = SHA256.Create()) {
                string actual = BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(typeof(object).Assembly.Location))).Replace("-", "").ToLowerInvariant();
                Console.WriteLine("LoadedCorlibSHA256={0}", actual);
                if (actual != args[2].ToLowerInvariant()) return 1;
            }
        }
        string key = "MonoTests.RegistrationServices.PermissionProbe." + Guid.NewGuid();
        try {
            using (RegistryKey probe = Registry.ClassesRoot.CreateSubKey(key)) probe.SetValue("probe", "write");
            Registry.ClassesRoot.DeleteSubKeyTree(key);
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        return 0;
    }
}
'@ | Set-Content $probeSource
    $probe = Join-Path $build 'NativeEnvironment.exe'
    & $csc /nologo "/platform:$Architecture" "/out:$probe" $probeSource
    if ($LASTEXITCODE -ne 0) { throw 'Environment probe compilation failed' }
    $bits = if ($Architecture -eq 'x86') { '32' } else { '64' }
    if ($Runtime -eq 'mono') {
        & $monoHost $runtimeRoot $probe $bits mono $candidateHash 2>&1 | Tee-Object -FilePath (Join-Path $output 'runtime-environment.log')
    } else {
        & $probe $bits 2>&1 | Tee-Object -FilePath (Join-Path $output 'runtime-environment.log')
    }
    if ($LASTEXITCODE -ne 0) { throw 'Native runtime, process architecture or registry permission probe failed' }

    $exitCode = 0
    $summaries = @()
    $excludedCategories = if ($Runtime -eq 'mono') { 'NotOnWindows,NotWorking,CAS,UI' } else { 'NotOnWindows,NotWorking,CAS,UI,NotDotNet' }
    foreach ($fixture in @('RegistrationServicesTest', 'RegistrationServicesRegistryTest')) {
        $xml = Join-Path $output "$fixture.xml"
        $testArgs = @((Join-Path $build 'RegistrationServices.Tests.dll'), "/run:MonoTests.System.Runtime.InteropServices.$fixture", '/noshadow', '/labels', '/nothread', "/exclude:$excludedCategories", "/xml:$xml")
        if ($Runtime -eq 'mono') {
            # Keep NUnit in the embedded Mono process; never delegate execution to native .NET.
            & $monoHost $runtimeRoot $runner @testArgs /framework:mono-4.0 /process:Single 2>&1 | Tee-Object -FilePath (Join-Path $output "$fixture.log")
        } else {
            & $runner @testArgs /framework:net-4.0 2>&1 | Tee-Object -FilePath (Join-Path $output "$fixture.log")
        }
        $runnerExit = $LASTEXITCODE
        Set-Content (Join-Path $output "$fixture.exit-code.txt") $runnerExit
        if (!(Test-Path $xml)) { throw "Missing NUnit results for $fixture (exit $runnerExit)" }
        [xml]$results = Get-Content $xml
        $cases = @($results.SelectNodes('//test-case'))
        $summary = [pscustomobject]@{
            fixture = $fixture
            totalDefined = if ($fixture -eq 'RegistrationServicesTest') { 2 } else { 10 }
            selected = $cases.Count
            filterExcluded = if ($Runtime -eq 'native' -and $fixture -eq 'RegistrationServicesRegistryTest') { 3 } else { 0 }
            passed = @($cases | Where-Object { $_.executed -eq 'True' -and $_.success -eq 'True' }).Count
            failed = @($cases | Where-Object { $_.executed -eq 'True' -and $_.success -ne 'True' }).Count
            skipped = @($cases | Where-Object { $_.executed -ne 'True' }).Count
            exitCode = $runnerExit
        }
        $summaries += $summary
        $summary | Format-List
        # A zero-test or ignored/permission-limited run is never considered successful.
        if ($runnerExit -ne 0 -or $summary.failed -gt 0 -or $summary.skipped -gt 0 -or $summary.selected -ne ($summary.totalDefined - $summary.filterExcluded)) {
            if ($exitCode -eq 0) { $exitCode = if ($runnerExit -ne 0) { $runnerExit } else { 1 } }
        }
    }
    $summaries | ConvertTo-Json | Set-Content (Join-Path $output 'summary.json')
} catch {
    Write-Output $_
    $exitCode = 1
} finally {
    Set-Content (Join-Path $output 'harness.exit-code.txt') $exitCode
    Stop-Transcript
}
exit $exitCode
