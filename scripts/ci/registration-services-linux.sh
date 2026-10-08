#!/usr/bin/env bash
# Focused real-corlib validation on native Linux, never Wine.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
output="$repo/artifacts/registration-services-linux-mono"
build="$output/build"
packages="$output/packages"
mkdir -p "$build" "$packages"
exec > >(tee "$output/harness.log") 2>&1
trap 'result=$?; printf "%s\n" "$result" > "$output/harness.exit-code.txt"' EXIT
source="$repo/mcs/class/corlib/Test/System.Runtime.InteropServices"
candidate="$repo/scripts/ci/registration-services-candidate"
git rev-parse HEAD > "$output/source-commit.txt"
uname -a > "$output/os-version.txt"
cat /etc/os-release >> "$output/os-version.txt"
mono --version | tee "$output/mono-version.txt"
dpkg-query -W mono-runtime mono-runtime-sgen mono-devel > "$output/mono-packages.txt"
sha256sum "$source"/RegistrationServices*.cs "$repo/mcs/class/corlib/Makefile" "$repo/mcs/class/mono.snk" > "$output/source-sha256.txt"
cp "$candidate/provenance.json" "$output/"
expected=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["corlibSha256"])' "$candidate/provenance.json")
echo "$expected  $candidate/mscorlib.dll" | sha256sum -c -

# Per-run machine registry and runtime files; leave HOME and the user registry untouched.
runtime=$(mktemp -d "$RUNNER_TEMP/registration-services-linux-runtime.XXXXXX")
export MONO_REGISTRY_PATH
MONO_REGISTRY_PATH=$(mktemp -d "$RUNNER_TEMP/registration-services-linux-registry.XXXXXX")
printf '%s\n' "$MONO_REGISTRY_PATH" > "$output/registry-store.txt"
mkdir -p "$runtime/lib/mono" "$runtime/etc"
cp -a /usr/lib/mono/4.5 /usr/lib/mono/gac "$runtime/lib/mono/"
cp -a /etc/mono "$runtime/etc/"
cp --remove-destination "$candidate/mscorlib.dll" "$runtime/lib/mono/4.5/mscorlib.dll"
gcc -Wall -Wextra "$repo/scripts/ci/registration-services-linux-host.c" -o "$build/mono-host" $(pkg-config --cflags --libs monosgen-2)
ldd "$build/mono-host" | tee "$output/launcher-libraries.txt"
engine=$(ldd "$build/mono-host" | awk '/libmonosgen-2.0.so/{print $3}')
sha256sum "$(readlink -f "$engine")" "$runtime/lib/mono/4.5/mscorlib.dll" > "$output/loaded-runtime-hashes.txt"

for id in NUnit NUnit.Runners; do
    lower=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
    curl --fail --location --retry 2 "https://api.nuget.org/v3-flatcontainer/$lower/2.6.4/$lower.2.6.4.nupkg" -o "$packages/$id.zip"
    unzip -q "$packages/$id.zip" -d "$packages/$id"
done
sha256sum "$packages"/*.zip > "$output/package-sha256.txt"
nunit=$(find "$packages/NUnit" -name nunit.framework.dll -print -quit)
runner=$(find "$packages/NUnit.Runners" -name nunit-console.exe -print -quit)
cp "$nunit" "$build/"
compile() {
    local name=$1 file=$2
    shift 2
    mkdir -p "$(dirname "$build/$name")"
    mcs -target:library -platform:anycpu "-out:$build/$name" "$@" "$source/$file"
}
compile RegistrationServicesTestAssembly.dll RegistrationServicesTestAssembly.cs
compile RegistrationServicesPIATestAssembly.dll RegistrationServicesTestAssembly.cs -define:PRIMARY_INTEROP_ASSEMBLY "-keyfile:$repo/mcs/class/mono.snk"
compile RegistrationVersion1/RegistrationServicesVersionedTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:VERSION_ONE
compile RegistrationVersion2/RegistrationServicesVersionedTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:VERSION_TWO
compile RegistrationServicesInvalidCallbackTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:INVALID_CALLBACK
compile RegistrationServicesGenericCallbackTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:GENERIC_CALLBACK
compile RegistrationServices.Tests.dll RegistrationServicesTest.cs "-r:$nunit"
mcs "-out:$build/LinuxEnvironment.exe" "$repo/scripts/ci/registration-services-linux-probe.cs"
"$build/mono-host" "$runtime" --runtime=v4.0 "$build/LinuxEnvironment.exe" "$expected" "$MONO_REGISTRY_PATH" | tee "$output/runtime-environment.log"

result=0
for fixture in RegistrationServicesTest RegistrationServicesRegistryTest; do
    set +e
    timeout 180 "$build/mono-host" "$runtime" --runtime=v4.0 "$runner" "$build/RegistrationServices.Tests.dll" "/run:MonoTests.System.Runtime.InteropServices.$fixture" /framework:mono-4.0 /process:Single /noshadow /labels /nothread /timeout:120000 /exclude:NotOnWindows,NotWorking,CAS,UI "/xml:$output/$fixture.xml" | tee "$output/$fixture.log"
    status=${PIPESTATUS[0]}
    set -e
    printf '%s\n' "$status" > "$output/$fixture.exit-code.txt"
    if [ "$status" -ne 0 ]; then result=$status; fi
done
find "$MONO_REGISTRY_PATH" -type f -print | sort > "$output/remaining-registry-files.txt"
python3 - "$output" <<'PY'
import json,pathlib,sys,xml.etree.ElementTree as ET
root=pathlib.Path(sys.argv[1]); summaries=[]; success=True
for fixture,total in [('RegistrationServicesTest',2),('RegistrationServicesRegistryTest',12)]:
    cases=list(ET.parse(root/(fixture+'.xml')).getroot().iter('test-case'))
    summary=dict(fixture=fixture,totalDefined=total,selected=len(cases),filterExcluded=0,
                 passed=sum(c.get('executed')=='True' and c.get('success')=='True' for c in cases),
                 failed=sum(c.get('executed')=='True' and c.get('success')!='True' for c in cases),
                 skipped=sum(c.get('executed')!='True' for c in cases),
                 exitCode=int((root/(fixture+'.exit-code.txt')).read_text()))
    summaries.append(summary)
    success &= summary['selected']==total and summary['passed']==total and summary['skipped']==0 and summary['exitCode']==0
(root/'summary.json').write_text(json.dumps(summaries,indent=2)+'\n')
print(json.dumps(summaries,indent=2))
sys.exit(0 if success else 1)
PY
exit "$result"
