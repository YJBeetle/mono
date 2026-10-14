#!/usr/bin/env bash
set -euo pipefail
root="$PWD/evidence"
lib="$PWD/mcs/class/lib/net_4_x-linux"
export MONO_PATH="$lib:$root" MONO_TLS_PROVIDER=btls
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$root/key.pem" -out "$root/certificate.pem" -days 1 -subj '/CN=WineMonoBtlsProbe'
openssl x509 -in "$root/certificate.pem" -outform DER -out "$root/certificate.der"
openssl pkcs12 -export -legacy -inkey "$root/key.pem" -in "$root/certificate.pem" -out "$root/certificate.pfx" -passout pass:
der=$(base64 -w 0 "$root/certificate.der")
pfx=$(base64 -w 0 "$root/certificate.pfx")
printf 'classlib\tmode\ttest\texit\tresult\n' > "$root/summary.txt"
failures=0
for classlib in baseline fixed; do
  cp "$root/$classlib/System.dll" "$lib/System.dll"
  cmp "$root/$classlib/System.dll" "$lib/System.dll"
  for mode in jit interp; do
    flags=()
    if [ "$mode" = interp ]; then flags=(--interpreter); fi
    probes='unit metadata'
    if [ "$classlib" = fixed ]; then
      probes='unit metadata managed-der managed-pkcs12 managed-properties managed-pkcs12-export managed-invalid loopback-tls native-cdecl native-default'
    fi
    for probe in $probes; do
      log="$root/$classlib-$mode-$probe.log"
      fixture="$der"
      case "$probe" in managed-pkcs12|managed-pkcs12-export|loopback-tls) fixture="$pfx";; esac
      set +e
      if [ "$probe" = unit ]; then
        xml="$root/$classlib-$mode-unit.xml"
        timeout -k 5 60 ./runtime/mono-wrapper "${flags[@]}" "$root/unit.exe" \
          -test:MonoTests.Mono.Btls.NativeCallingConventionTest -format:nunit2 "-result:$xml" > "$log" 2>&1
      else
        timeout -k 5 60 ./runtime/mono-wrapper "${flags[@]}" "$root/btls.exe" "$probe" "$fixture" "$der" > "$log" 2>&1
      fi
      code=$?
      set -e
      result=FAIL
      if [ "$probe" = unit ]; then
        # Both the negative baseline and passing fixed fixture must execute;
        # missing, ignored or timed-out unit tests never satisfy this check.
        if { [ "$classlib" = baseline ] && [ "$code" = 1 ]; } || { [ "$classlib" = fixed ] && [ "$code" = 0 ]; }; then
          if python3 - "$xml" "$classlib" <<'PY'
import sys
import xml.etree.ElementTree as ET
cases = ET.parse(sys.argv[1]).findall('.//test-case')
assert len(cases) == 1
case = cases[0]
assert case.get('executed') == 'True'
assert case.get('name').endswith('NativeImportsAndCallbacksUseCdecl')
assert case.get('success') == ('False' if sys.argv[2] == 'baseline' else 'True')
if sys.argv[2] == 'baseline':
    failure = ''.join(case.find('failure').itertext())
    assert 'Cdecl' in failure and 'Winapi' in failure
PY
          then result=PASS; fi
        fi
      elif [ "$classlib" = baseline ]; then
        if [ "$code" = 1 ] && grep -Fq 'BTLS_ABI_NOT_CDECL=Mono.Btls.' "$log"; then result=BASELINE_METADATA_MISMATCH; fi
      elif [ "$code" = 0 ] && grep -Fxq "PROBE_PASS=$probe" "$log" &&
           grep -Fxq "POINTER_SIZE=$BTLS_EXPECTED_POINTER_SIZE" "$log" &&
           grep -Fxq "SYSTEM_ASSEMBLY=$lib/System.dll" "$log" &&
           ! grep -Eq 'Assertion at|Unhandled Exception|Native Crash Reporting' "$log"; then
        result=PASS
      fi
      if [ "$result" = FAIL ]; then failures=$((failures + 1)); fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$classlib" "$mode" "$probe" "$code" "$result" >> "$root/summary.txt"
      cat "$log"
    done
  done
done
cat "$root/summary.txt"
test "$failures" = 0
echo BTLS_MAIN_LINUX_MATRIX_PASS
