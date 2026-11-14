import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
workflow = (root / ".github/workflows/release-homebrew-interface.yml").read_text()
start = "# homebrew-formula-bump:start"
end = "# homebrew-formula-bump:end"
assert start in workflow and end in workflow, "formula bump must be executable in isolation"
script = "\n".join(line[10:] for line in workflow.split(start, 1)[1].split(end, 1)[0].splitlines())

mock = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
base=Path(os.environ["FIXTURE"])
if "PUT" in args:
    fields=dict(x.split("=",1) for i,x in enumerate(args) if i and args[i-1]=="-f")
    (base/"put.json").write_text(json.dumps(fields))
elif any("releases/tags/" in x for x in args):
    print(json.dumps({"assets":[{"name":"mcog.tar.gz","url":"https://api.github.com/repos/example/tap/releases/assets/123"}]}))
else:
    print((base/"formula.json").read_text())
'''

for private in (True, False):
    with tempfile.TemporaryDirectory(prefix="private-formula-") as temporary:
        base = Path(temporary)
        tools = base / "bin"
        tools.mkdir()
        gh = tools / "gh"
        gh.write_text(mock)
        gh.chmod(0o755)
        source = 'class Mcog < Formula\n  url "old"' + (',\n      using: GitHubPrivateReleaseAssetDownloadStrategy' if private else '')
        source += '\n  version "0.0.0"\n  sha256 "old"\nend\n'
        (base / "formula.json").write_text(json.dumps({
            "sha": "original-sha", "content": base64.b64encode(source.encode()).decode(),
        }))
        (base / "mcog.tar.gz").write_bytes(b"fixture")
        (base / "mcog.tar.gz.sha256").write_text("a" * 64 + "  mcog.tar.gz\n")
        env = dict(os.environ, PATH=str(tools) + ":" + os.environ["PATH"],
                   FIXTURE=str(base), GH_REPO="example/tap", DESTINATION_TAG="mcog-v0.1.0",
                   FORMULA_PATH="Formula/mcog.rb", VERSION="0.1.0",
                   GITHUB_REF_NAME="mcog/v0.1.0", PRIVATE_ASSET=str(private).lower())
        subprocess.run(["sh", "-eu", "-c", script], cwd=base, env=env, check=True)
        fields = json.loads((base / "put.json").read_text())
        updated = base64.b64decode(fields["content"]).decode()
        url = ("https://api.github.com/repos/example/tap/releases/assets/123" if private else
               "https://github.com/example/tap/releases/download/mcog-v0.1.0/mcog.tar.gz")
        assert f'  url "{url}"' in updated, updated
        assert '  version "0.1.0"' in updated
        assert '  sha256 "' + "a" * 64 + '"' in updated
        assert fields["sha"] == "original-sha"
        assert ("using: GitHubPrivateReleaseAssetDownloadStrategy" in updated) == private

print("private and public formula bump behavior passed")
