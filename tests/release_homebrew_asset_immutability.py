import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
workflow = (root / ".github/workflows/release-homebrew-interface.yml").read_text()
canonical = (root / "tests/fixtures/reconcile_release_assets.sh").read_text().rstrip()
start = "# release-asset-reconciliation:start"
end = "# release-asset-reconciliation:end"
assert start in workflow and end in workflow
embedded = workflow.split(start, 1)[1].split(end, 1)[0]
embedded = "\n".join(line[10:] if line.startswith(" " * 10) else line for line in embedded.splitlines())
assert embedded.strip("\n") == canonical


mock_gh = r'''#!/bin/sh
set -eu
shift # release
verb=$1
shift
case "$verb" in
  view)
    if [ "$#" -gt 1 ]; then
      for path in "$MOCK_REMOTE"/*; do
        [ -f "$path" ] && basename "$path"
      done
    fi
    ;;
  download)
    shift # tag
    [ "$1" = "--pattern" ]
    asset=$2
    [ "$3" = "--dir" ]
    cp "$MOCK_REMOTE/$asset" "$4/$asset"
    ;;
  upload)
    shift # tag
    asset=$1
    cp "$asset" "$MOCK_REMOTE/$asset"
    printf '%s\n' "$asset" >> "$MOCK_UPLOAD_LOG"
    ;;
  *) exit 2 ;;
esac
'''


def run_case(remote_archive: bytes | None, remote_checksum: bytes | None):
    with tempfile.TemporaryDirectory(prefix="release-asset-immutability-") as temporary:
        work = Path(temporary)
        remote = work / "remote"
        tools = work / "bin"
        remote.mkdir()
        tools.mkdir()
        archive = "world-modeler.tar.gz"
        checksum = f"{archive}.sha256"
        (work / archive).write_bytes(b"archive-bytes")
        (work / checksum).write_bytes(b"archive-checksum\n")
        if remote_archive is not None:
            (remote / archive).write_bytes(remote_archive)
        if remote_checksum is not None:
            (remote / checksum).write_bytes(remote_checksum)
        gh = tools / "gh"
        gh.write_text(mock_gh)
        gh.chmod(0o755)
        upload_log = work / "uploads"
        env = {
            **os.environ,
            "PATH": f"{tools}:{os.environ['PATH']}",
            "DESTINATION_TAG": "world-modeler-v1.1.0",
            "archive": archive,
            "checksum": checksum,
            "MOCK_REMOTE": str(remote),
            "MOCK_UPLOAD_LOG": str(upload_log),
        }
        result = subprocess.run(
            ["sh", str(root / "tests/fixtures/reconcile_release_assets.sh")],
            cwd=work,
            env=env,
            capture_output=True,
            text=True,
        )
        uploads = upload_log.read_text().splitlines() if upload_log.exists() else []
        return result, uploads, {path.name: path.read_bytes() for path in remote.iterdir()}


identical, uploads, _ = run_case(b"archive-bytes", b"archive-checksum\n")
assert identical.returncode == 0 and uploads == []

drifted, uploads, _ = run_case(b"different", b"archive-checksum\n")
assert drifted.returncode != 0 and uploads == []
assert "release asset differs from the existing immutable asset" in drifted.stderr

partial, uploads, remote = run_case(b"archive-bytes", None)
assert partial.returncode == 0 and uploads == ["world-modeler.tar.gz.sha256"]
assert remote["world-modeler.tar.gz"] == b"archive-bytes"
assert remote["world-modeler.tar.gz.sha256"] == b"archive-checksum\n"

print("release asset immutability contract ok")
