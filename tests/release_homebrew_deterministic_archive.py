import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile


root = Path(__file__).resolve().parents[1]
workflow = (root / ".github/workflows/release-homebrew-interface.yml").read_text()
canonical = (root / "tests/fixtures/deterministic_release_archive.py").read_text().rstrip()
start = "# deterministic-archive-script:start"
end = "# deterministic-archive-script:end"
assert start in workflow, "workflow is missing the deterministic archive script start marker"
assert end in workflow, "workflow is missing the deterministic archive script end marker"
embedded = workflow.split(start, 1)[1].split(end, 1)[0]
embedded = "\n".join(line[10:] if line.startswith(" " * 10) else line for line in embedded.splitlines())
embedded = embedded.strip("\n")
assert embedded == canonical, "workflow packager differs from its executable contract fixture"


def populate(directory: Path, reverse: bool, timestamp: int):
    operations = [
        lambda: (directory / "share").mkdir(),
        lambda: (directory / "bin").mkdir(),
        lambda: (directory / "share/model.json").write_text('{"ok":true}\n'),
        lambda: (directory / "bin/world-modeler").write_bytes(b"#!/bin/sh\nexit 0\n"),
        lambda: (directory / "bin-notes").write_text("release notes\n"),
        lambda: (directory / "world-modeler").symlink_to("bin/world-modeler"),
    ]
    for operation in operations[::-1] if reverse else operations:
        try:
            operation()
        except FileNotFoundError:
            for parent in [directory / "bin", directory / "share"]:
                parent.mkdir(exist_ok=True)
            operation()
        except FileExistsError:
            pass
    os.chmod(directory / "bin/world-modeler", 0o751)
    for path in directory.rglob("*"):
        if not path.is_symlink():
            os.utime(path, (timestamp, timestamp))


with tempfile.TemporaryDirectory(prefix="deterministic-release-archive-") as temporary:
    workspace = Path(temporary)
    sources = [workspace / "first", workspace / "second"]
    for source in sources:
        source.mkdir()
    populate(sources[0], reverse=False, timestamp=1_000_000_000)
    populate(sources[1], reverse=True, timestamp=2_000_000_000)

    archives = [workspace / "first.tar.gz", workspace / "second.tar.gz"]
    receipts = [workspace / "first.json", workspace / "second.json"]
    script = root / "tests/fixtures/deterministic_release_archive.py"
    for source, archive, receipt in zip(sources, archives, receipts):
        subprocess.run(["python3", script, source, archive, receipt], check=True)

    assert archives[0].read_bytes() == archives[1].read_bytes()
    expected_hash = hashlib.sha256(archives[0].read_bytes()).hexdigest()
    assert expected_hash == "4fe08ed6e5b13cc6c92bfb10fc1f6d49d49a45820b7e46d2e853f6fd6e386507"
    parsed = [json.loads(receipt.read_text()) for receipt in receipts]
    assert parsed[0]["entries"] == parsed[1]["entries"]
    assert parsed[0]["archive"] == parsed[1]["archive"]
    assert set(parsed[0]["toolchain"]) == {"python", "zlib"}
    assert parsed[0]["archive"]["sha256"] == expected_hash
    assert parsed[0]["normalized"] == {
        "directory_mode": "0755",
        "executable_mode": "0755",
        "file_mode": "0644",
        "gid": 0,
        "gname": "",
        "mtime": 0,
        "order": "utf8-bytewise-path",
        "symlink_mode": "0777",
        "uid": 0,
        "uname": "",
    }
    with tarfile.open(archives[0], "r:gz") as archive:
        members = archive.getmembers()
        assert [member.name for member in members] == [
            "bin", "bin-notes", "bin/world-modeler", "share", "share/model.json", "world-modeler",
        ]
        for member in members:
            assert member.uid == 0 and member.gid == 0
            assert member.uname == "" and member.gname == "" and member.mtime == 0
        executable = next(member for member in members if member.name == "bin/world-modeler")
        assert stat.S_IMODE(executable.mode) == 0o755

    rejected = workspace / "rejected"
    rejected.mkdir()
    for name, target, message in [
        ("absolute", "/outside", "absolute archive symlink is not allowed"),
        ("escaping", "../outside", "escaping archive symlink is not allowed"),
    ]:
        candidate = rejected / name
        candidate.mkdir()
        (candidate / "unsafe").symlink_to(target)
        result = subprocess.run(
            ["python3", script, candidate, workspace / f"{name}.tar.gz", workspace / f"{name}.json"],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0 and message in result.stderr

    unsupported = rejected / "unsupported"
    unsupported.mkdir()
    os.mkfifo(unsupported / "pipe")
    result = subprocess.run(
        ["python3", script, unsupported, workspace / "unsupported.tar.gz", workspace / "unsupported.json"],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0 and "unsupported archive entry type" in result.stderr

print("deterministic homebrew release archive ok")
