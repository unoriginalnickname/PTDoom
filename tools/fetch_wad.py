"""Download the Doom shareware IWAD (v1.9) and verify it.

The WAD is not kept in the repo: id Software's shareware licence lets it be
shared unmodified, but it isn't ours to relicense. This takes it from
Debian's official doom-wad-shareware package and checks the known SHA-1 of
the v1.9 shareware release.
"""
import hashlib
import io
import pathlib
import subprocess
import sys
import tarfile
import tempfile

from paths import WAD as DEST

URL = ("https://deb.debian.org/debian/pool/non-free/d/doom-wad-shareware/"
       "doom-wad-shareware_1.9.fixed-5_all.deb")
SHA1 = "5b2e249b9c5133ec987b3ea77596381dc0d6bc1d"


def wad_from_deb(deb: bytes) -> bytes:
    """Pull doom1.wad out of a .deb (an ar archive holding data.tar.*)."""
    if deb[:8] != b"!<arch>\n":
        raise ValueError("not a .deb")
    pos = 8
    while pos < len(deb):
        header = deb[pos:pos + 60]
        name = header[:16].decode().strip()
        size = int(header[48:58])
        body = deb[pos + 60:pos + 60 + size]
        if name.startswith("data.tar"):
            with tarfile.open(fileobj=io.BytesIO(body)) as tar:
                for member in tar.getmembers():
                    if member.name.endswith("/doom1.wad"):
                        return tar.extractfile(member).read()
        pos += 60 + size + size % 2
    raise ValueError("doom1.wad not found in package")


def main() -> int:
    if DEST.exists() and hashlib.sha1(DEST.read_bytes()).hexdigest() == SHA1:
        print(f"already present: {DEST}")
        return 0
    print(f"downloading {URL}")
    with tempfile.TemporaryDirectory() as tmp:
        deb = pathlib.Path(tmp) / "wad.deb"
        # curl rather than urllib: on Windows curl uses the system certificate
        # store, which also covers TLS-inspecting proxies that Python rejects.
        subprocess.run(["curl", "-fsSL", "-o", str(deb), URL], check=True)
        wad = wad_from_deb(deb.read_bytes())
    got = hashlib.sha1(wad).hexdigest()
    if got != SHA1:
        print(f"SHA-1 mismatch: got {got}, expected {SHA1}", file=sys.stderr)
        return 1
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_bytes(wad)
    print(f"ok: {DEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
