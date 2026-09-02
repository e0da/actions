import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import stat
import sys
import tarfile
import zlib


source = Path(sys.argv[1]).resolve(strict=True)
archive = Path(sys.argv[2]).resolve()
receipt = Path(sys.argv[3]).resolve()
if not source.is_dir():
    raise SystemExit("deterministic archive source must be a directory")
if archive == source or source in archive.parents:
    raise SystemExit("deterministic archive output must be outside the source")


def entries_under(directory: Path, prefix: PurePosixPath = PurePosixPath()):
    entries = sorted(os.scandir(directory), key=lambda entry: entry.name.encode("utf-8"))
    for entry in entries:
        relative = prefix / entry.name
        path = Path(entry.path)
        mode = entry.stat(follow_symlinks=False).st_mode
        if stat.S_ISDIR(mode):
            yield path, relative, "directory", 0, ""
            yield from entries_under(path, relative)
        elif stat.S_ISREG(mode):
            yield path, relative, "file", entry.stat(follow_symlinks=False).st_size, ""
        elif stat.S_ISLNK(mode):
            target = os.readlink(path)
            if target.startswith("/"):
                raise SystemExit(f"absolute archive symlink is not allowed: {relative}")
            resolved = relative.parent
            for part in PurePosixPath(target).parts:
                if part == "..":
                    if not resolved.parts:
                        raise SystemExit(f"escaping archive symlink is not allowed: {relative}")
                    resolved = resolved.parent
                elif part not in ("", "."):
                    resolved /= part
            yield path, relative, "symlink", 0, target
        else:
            raise SystemExit(f"unsupported archive entry type: {relative}")


normalized = []
archive.parent.mkdir(parents=True, exist_ok=True)
with archive.open("wb") as raw:
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as tar:
            for path, relative, kind, size, link_target in sorted(
                entries_under(source), key=lambda item: item[1].as_posix().encode("utf-8")
            ):
                name = relative.as_posix()
                info = tarfile.TarInfo(name)
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                info.mtime = 0
                info.pax_headers = {}
                if kind == "directory":
                    info.type = tarfile.DIRTYPE
                    info.mode = 0o755
                    tar.addfile(info)
                elif kind == "symlink":
                    info.type = tarfile.SYMTYPE
                    info.mode = 0o777
                    info.linkname = link_target
                    tar.addfile(info)
                else:
                    info.type = tarfile.REGTYPE
                    info.mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                    info.size = size
                    with path.open("rb") as body:
                        tar.addfile(info, body)
                normalized.append({
                    "path": name,
                    "type": kind,
                    "mode": f"{info.mode:04o}",
                    "size": info.size,
                    **({"link_target": link_target} if link_target else {}),
                })

archive_bytes = archive.read_bytes()
receipt.write_text(json.dumps({
    "schema_version": 1,
    "mode": "deterministic",
    "archive_format": "pax",
    "compression": {"format": "gzip", "level": 9, "mtime": 0, "filename": ""},
    "toolchain": {"python": platform.python_version(), "zlib": zlib.ZLIB_VERSION},
    "normalized": {
        "order": "utf8-bytewise-path",
        "uid": 0,
        "gid": 0,
        "uname": "",
        "gname": "",
        "mtime": 0,
        "directory_mode": "0755",
        "executable_mode": "0755",
        "file_mode": "0644",
        "symlink_mode": "0777",
    },
    "entries": normalized,
    "archive": {
        "size": len(archive_bytes),
        "sha256": hashlib.sha256(archive_bytes).hexdigest(),
    },
}, sort_keys=True, indent=2) + "\n")
