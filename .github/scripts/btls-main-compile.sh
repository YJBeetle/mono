#!/usr/bin/env bash
set -euo pipefail
root="$PWD"
lib="$root/mcs/class/lib/net_4_x-linux"
references=()
for assembly in mscorlib System System.Core System.Xml; do
  test -s "$lib/$assembly.dll"
  references+=("-r:$lib/$assembly.dll")
done
csc=$(dotnet --list-sdks | awk '$1 ~ /^8\./ {v=$1; gsub(/[\[\]]/, "", $2); p=$2} END {print p "/" v "/Roslyn/bincore/csc.dll"}')
test -s "$csc"
(cd mcs/tools/nunit-lite/NUnitLite &&
 dotnet "$csc" -nologo -target:library -nostdlib+ "${references[@]}" \
   -define:MONO,__MOBILE__,TRACE,DEBUG,NET_4_0,CLR_4_0,NUNITLITE \
   -out:"$root/evidence/nunitlite.dll" @nunitlite.dll.sources)
dotnet "$csc" -nologo -nostdlib+ "${references[@]}" \
  -r:evidence/nunitlite.dll -out:evidence/unit.exe \
  mcs/class/System/Test/Mono.Btls/NativeCallingConventionTest.cs \
  mcs/tools/nunit-lite/nunit-lite-console/Console.cs
dotnet "$csc" -nologo -nostdlib+ "${references[@]}" \
  -out:evidence/btls.exe .github/fixtures/btls/BtlsProbe.cs
