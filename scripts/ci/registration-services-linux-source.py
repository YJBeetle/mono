"""Explicit source-level Linux harness; never claim this replaces the real corlib."""
import hashlib
import json
import pathlib
import sys

repo, build = map(pathlib.Path, sys.argv[1:3])
interop = repo / "mcs/class/corlib/System.Runtime.InteropServices"
registration = (interop / "RegistrationServices.cs").read_text()
marshal = (interop / "Marshal.cs").read_text()
tests = (repo / "mcs/class/corlib/Test/System.Runtime.InteropServices/RegistrationServicesTest.cs").read_text()
method_start = marshal.index("\t\tpublic static bool IsTypeVisibleFromCom (Type t)")
brace_start = marshal.index("{", method_start)
depth = 1
end = brace_start + 1
while depth:
    depth += (marshal[end] == "{") - (marshal[end] == "}")
    end += 1
method = marshal[method_start:end]
attribute = '\t\t[MonoTODO ("implement")]\n'
assert registration.count(attribute) == 3
assert registration.count("Marshal.IsTypeVisibleFromCom (type)") == 1
registration = registration.replace(attribute, "").replace(
    "Marshal.IsTypeVisibleFromCom (type)", "PrMarshal.IsTypeVisibleFromCom (type)")
tests = tests.replace("Marshal.IsTypeVisibleFromCom (", "PrMarshal.IsTypeVisibleFromCom (")
(build / "PR.RegistrationServices.cs").write_text(registration)
(build / "PR.MarshalVisibility.cs").write_text(
    "using System;\nnamespace System.Runtime.InteropServices {\npublic static class PrMarshal {\n" + method + "\n}\n}\n")
(build / "PR.RegistrationServicesTest.cs").write_text(tests)
manifest = {
    "mode": "Source-level PR managed implementation on native Linux Mono; NOT a rebuilt or candidate corlib",
    "originalRegistrationServicesSha256": hashlib.sha256((interop / "RegistrationServices.cs").read_bytes()).hexdigest(),
    "originalMarshalSha256": hashlib.sha256((interop / "Marshal.cs").read_bytes()).hexdigest(),
    "visibilityMethodSha256": hashlib.sha256(method.encode()).hexdigest(),
    "transforms": [
        "Remove exactly three internal MonoTODO annotations to permit standalone compilation",
        "Extract the exact PR Marshal.IsTypeVisibleFromCom body into public PrMarshal helper",
        "Route RegistrationServices' single visibility call and the visibility test assertions to that helper",
        "Compile PR RegistrationServices in the fixture DLL, shadowing the system class; all other Marshal/registry/runtime APIs remain Ubuntu Mono's",
    ],
}
(build.parent / "source-harness-provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
