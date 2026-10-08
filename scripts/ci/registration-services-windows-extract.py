"""Extract existing runtime files and dereference archive links on Windows."""
import json
import lzma
import pathlib
import shutil
import sys
import tarfile
import tempfile

archive, destination = map(pathlib.Path, sys.argv[1:3])
prefixes = tuple("wine-mono-11.3.0/" + suffix for suffix in (
    "bin/", "lib/mono/4.5/", "lib/mono/gac/", "lib/x86/", "lib/x86_64/", "etc/mono/",
))
files = links = size = 0
with tempfile.TemporaryFile() as uncompressed:
    # Link targets occur later in the archive. Decompress once so resolving each
    # link does not repeatedly seek/reinflate the entire XZ stream.
    with lzma.open(archive, "rb") as compressed:
        shutil.copyfileobj(compressed, uncompressed)
    uncompressed.seek(0)
    package = tarfile.open(fileobj=uncompressed, mode="r:")
    for member in package.getmembers():
        if not member.name.startswith(prefixes) or member.isdir():
            continue
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("Unsafe archive path: " + member.name)
        if not (member.isfile() or member.issym() or member.islnk()):
            raise ValueError("Unsupported archive entry: " + member.name)
        target = destination.joinpath(*path.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        # extractfile resolves links against entries inside this verified archive.
        # Write the target's identical bytes, with no Windows symlink privilege dependency.
        with package.extractfile(member) as source, target.open("wb") as output:
            shutil.copyfileobj(source, output)
        files += 1
        links += int(member.issym() or member.islnk())
        size += target.stat().st_size
    package.close()
print(json.dumps({"files": files, "dereferencedLinks": links, "bytes": size,
                  "policy": "Existing runtime files only; archive symlinks copied as identical regular files"}))
