#!/usr/bin/env bash
# Build matching native Linux engine/corlib and execute untransformed repository tests.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
output="$repo/artifacts/registration-services-matching-linux"
work="$RUNNER_TEMP/registration-services-matching-linux"
prefix="$work/prefix"
build="$output/tests"
mkdir -p "$output" "$work"
exec > >(tee -a "$output/harness.log") 2>&1
phase=${1:?identity, build or test required}
trap 'status=$?; printf "%s\n" "$status" > "$output/$phase.exit-code.txt"' EXIT
flags=("--prefix=$prefix" --with-mcs-docs=no --disable-system-aot --without-compiler-server --without-mcs-docs --disable-boehm)

case "$phase" in
identity)
    git rev-parse HEAD > "$output/test-source-commit.txt"
    git ls-tree -r HEAD > "$output/git-source-tree.txt"
    uname -a > "$output/os-version.txt"
    cat /etc/os-release >> "$output/os-version.txt"
    gcc --version > "$output/compiler-version.txt"
    printf '%s\n' "${flags[@]}" > "$output/configure-flags.txt"
    python3 - "$output" "$repo" <<'PY'
import hashlib,json,pathlib,subprocess,sys
output,repo=map(pathlib.Path,sys.argv[1:])
rows=(output/'git-source-tree.txt').read_text().splitlines()
rows=[r for r in rows if not r.split('\t',1)[1].startswith(('.github/','scripts/ci/registration-services-'))
      and r.split('\t',1)[1]!='mcs/class/corlib/Test/System.Runtime.InteropServices/RegistrationServicesTest.cs']
identity=hashlib.sha256(('\n'.join(rows)+'\n').encode()).hexdigest()
procedure=(repo/'scripts/ci/registration-services-linux-matching.sh').read_text().split('\nbuild)\n',1)[1].split('\ntest)\n',1)[0]
settings=(output/'configure-flags.txt').read_bytes()+(output/'compiler-version.txt').read_bytes()+procedure.encode()
key=hashlib.sha256(identity.encode()+settings).hexdigest()
(output/'source-identity.json').write_text(json.dumps({'runtimeSourceIdentity':identity,'cacheKey':key,'testCommit':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),'excludedFromRuntimeIdentity':['.github/','scripts/ci/registration-services-*','RegistrationServicesTest.cs only; tests rebuilt every run']},indent=2)+'\n')
(output/'cache-key.txt').write_text(key+'\n')
print('Runtime source identity:',identity,'cache key:',key)
PY
    printf 'key=%s\n' "$(cat "$output/cache-key.txt")" >> "$GITHUB_OUTPUT"
    ;;
build)
    if [ -f "$work/build-provenance.json" ]; then
        python3 - "$output" "$work" <<'PY'
import json,pathlib,sys
output,work=map(pathlib.Path,sys.argv[1:])
current=json.loads((output/'source-identity.json').read_text()); original=json.loads((work/'build-provenance.json').read_text())
assert current['cacheKey']==original['cacheKey']
assert current['runtimeSourceIdentity']==original['runtimeSourceIdentity']
print('Verified cached source/configuration association:',original)
PY
        (cd "$work" && sha256sum -c product-sha256.txt)
        echo 'Reusing a source/configuration/hash-verified matching native build'
    else
        git submodule init
        git config submodule.external/reference-assemblies.url https://github.com/wine-mono/reference-assemblies.git
        git submodule update --init --recursive --depth 1 2>&1 | tee "$work/submodule-checkout.log"
        git submodule status --recursive | tee "$work/submodule-sources.txt"
        # Disable only the unused Boehm engine; SGen, the Linux JIT and class library stay enabled.
        NOCONFIGURE=yes ./autogen.sh --disable-boehm 2>&1 | tee "$work/autogen.log"
        mkdir -p "$work/build"
        (cd "$work/build" && "$repo/configure" "${flags[@]}") 2>&1 | tee "$work/configure.log"
        make -C "$work/build" -j2 2>&1 | tee "$work/build.log"
        make -C "$work/build" install 2>&1 | tee "$work/install.log"
        git diff --exit-code --submodule=short
        python3 - "$output" "$work" <<'PY'
import json,os,pathlib,subprocess,sys
output,work=map(pathlib.Path,sys.argv[1:]); record=json.loads((output/'source-identity.json').read_text())
record.update(buildCommit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),buildRun='https://github.com/'+os.environ['GITHUB_REPOSITORY']+'/actions/runs/'+os.environ['GITHUB_RUN_ID'],configureFlags=(output/'configure-flags.txt').read_text().splitlines(),sourceChanges='None; configure/build must pass git diff --exit-code including submodules',profile='net_4_x-linux',engine='native Linux x64 SGen/JIT; Boehm and system AOT disabled')
(work/'build-provenance.json').write_text(json.dumps(record,indent=2)+'\n')
PY
        (cd "$work" && sha256sum prefix/bin/mono-sgen prefix/lib/mono/4.5/mscorlib.dll prefix/lib/mono/4.5/System.dll prefix/lib/mono/4.5/System.Core.dll prefix/lib/mono/4.5/System.Xml.dll > product-sha256.txt)
    fi
    cp "$work/build-provenance.json" "$work/product-sha256.txt" "$output/"
    cp "$work"/*.log "$work/submodule-sources.txt" "$output/"
    "$prefix/bin/mono" --version | tee "$output/matching-mono-version.txt"
    test -s "$prefix/lib/mono/4.5/mscorlib.dll"
    cp "$prefix/bin/mono-sgen" "$prefix/lib/mono/4.5/mscorlib.dll" "$output/"
    ;;
test)
    mkdir -p "$build" "$output/packages"
    source="$repo/mcs/class/corlib/Test/System.Runtime.InteropServices"
    sha256sum "$source"/RegistrationServices*.cs "$repo/mcs/class/corlib/System.Runtime.InteropServices/RegistrationServices.cs" "$repo/mcs/class/corlib/System.Runtime.InteropServices/Marshal.cs" "$repo/mcs/class/corlib/Makefile" "$repo/mcs/class/mono.snk" > "$output/executed-source-sha256.txt"
    export MONO_REGISTRY_PATH
    MONO_REGISTRY_PATH=$(mktemp -d "$RUNNER_TEMP/registration-services-matching-registry.XXXXXX")
    printf '%s\n' "$MONO_REGISTRY_PATH" > "$output/registry-store.txt"
    for id in NUnit NUnit.Runners; do
        lower=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
        curl --fail --location --retry 2 "https://api.nuget.org/v3-flatcontainer/$lower/2.6.4/$lower.2.6.4.nupkg" -o "$output/packages/$id.zip"
        unzip -q "$output/packages/$id.zip" -d "$output/packages/$id"
    done
    sha256sum "$output/packages"/*.zip > "$output/package-sha256.txt"
    nunit=$(find "$output/packages/NUnit" -name nunit.framework.dll -print -quit)
    runner=$(find "$output/packages/NUnit.Runners" -name nunit-console.exe -print -quit)
    cp "$nunit" "$build/"
    compile() {
        local name=$1 file=$2
        shift 2
        mkdir -p "$(dirname "$build/$name")"
        "$prefix/bin/mcs" -target:library -platform:anycpu "-out:$build/$name" "$@" "$source/$file"
    }
    compile RegistrationServicesTestAssembly.dll RegistrationServicesTestAssembly.cs
    compile RegistrationServicesPIATestAssembly.dll RegistrationServicesTestAssembly.cs -define:PRIMARY_INTEROP_ASSEMBLY "-keyfile:$repo/mcs/class/mono.snk"
    compile RegistrationVersion1/RegistrationServicesVersionedTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:VERSION_ONE
    compile RegistrationVersion2/RegistrationServicesVersionedTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:VERSION_TWO
    compile RegistrationServicesInvalidCallbackTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:INVALID_CALLBACK
    compile RegistrationServicesGenericCallbackTestAssembly.dll RegistrationServicesBoundaryTestAssembly.cs -define:GENERIC_CALLBACK
    # Original repository test source, compiled alone: no shadow implementation or visibility helper.
    compile RegistrationServices.Tests.dll RegistrationServicesTest.cs "-r:$nunit"
    "$prefix/bin/mcs" "-out:$build/MatchingLinuxEnvironment.exe" "$repo/scripts/ci/registration-services-linux-matching-probe.cs"
    expected=$(sha256sum "$prefix/lib/mono/4.5/mscorlib.dll" | cut -d ' ' -f 1)
    "$prefix/bin/mono" "$build/MatchingLinuxEnvironment.exe" "$expected" "$MONO_REGISTRY_PATH" "$prefix" "$build/RegistrationServices.Tests.dll" | tee "$output/runtime-environment.log"
    result=0
    for fixture in RegistrationServicesTest RegistrationServicesRegistryTest; do
        set +e
        timeout 180 "$prefix/bin/mono" "$runner" "$build/RegistrationServices.Tests.dll" "-run:MonoTests.System.Runtime.InteropServices.$fixture" -framework:mono-4.0 -process:Single -noshadow -labels -nothread -timeout:120000 -exclude:NotOnWindows,NotWorking,CAS,UI "-xml:$output/$fixture.xml" | tee "$output/$fixture.log"
        status=${PIPESTATUS[0]}
        set -e
        printf '%s\n' "$status" > "$output/$fixture.exit-code.txt"
        if [ "$status" -ne 0 ]; then result=$status; fi
    done
    "$prefix/bin/mono" "$build/MatchingLinuxEnvironment.exe" "$expected" "$MONO_REGISTRY_PATH" "$prefix" "$build/RegistrationServices.Tests.dll" cleanup | tee "$output/cleanup-verification.log"
    find "$MONO_REGISTRY_PATH" -type f -print | sort > "$output/remaining-registry-files.txt"
    python3 - "$output" <<'PY'
import json,pathlib,sys,xml.etree.ElementTree as ET
root=pathlib.Path(sys.argv[1]); summaries=[]; success=True
for fixture,total in [('RegistrationServicesTest',2),('RegistrationServicesRegistryTest',12)]:
    cases=list(ET.parse(root/(fixture+'.xml')).getroot().iter('test-case'))
    summary=dict(fixture=fixture,totalDefined=total,selected=len(cases),filterExcluded=0,
                 passed=sum(c.get('executed')=='True' and c.get('success')=='True' for c in cases),
                 failed=sum(c.get('executed')=='True' and c.get('success')!='True' for c in cases),
                 skipped=sum(c.get('executed')!='True' for c in cases),exitCode=int((root/(fixture+'.exit-code.txt')).read_text()))
    summaries.append(summary)
    success &= summary['selected']==total and summary['passed']==total and summary['skipped']==0 and summary['exitCode']==0
(root/'summary.json').write_text(json.dumps(summaries,indent=2)+'\n')
print(json.dumps(summaries,indent=2)); sys.exit(0 if success else 1)
PY
    exit "$result"
    ;;
*) exit 1 ;;
esac
