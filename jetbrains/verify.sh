#!/usr/bin/env bash
# Verify that the package has the intended TFMs and preserves the pre-existing dependency groups.
set -euo pipefail
fork=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$fork")
revision=${1:-1}
expected_version="9.10.3.$revision"
shopt -s nullglob
packages=("$root"/artifacts/jetbrains/packages/Microsoft.Extensions.AI.Abstractions."$expected_version".nupkg)
if [ "${#packages[@]}" -ne 1 ]; then
  echo "Expected one Microsoft.Extensions.AI.Abstractions.$expected_version.nupkg in artifacts/jetbrains/packages" >&2
  exit 1
fi

python3 - "${packages[0]}" "$expected_version" <<'PY'
import sys
import zipfile
import xml.etree.ElementTree as ET

package, expected_version = sys.argv[1:]
namespace = {'n': 'http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd'}
with zipfile.ZipFile(package) as archive:
    names = archive.namelist()
    tfms = {
        name.split('/')[1]
        for name in names
        if name.startswith('lib/') and len(name.split('/')) > 2
    }
    expected_tfms = {'net462', 'net8.0', 'netstandard2.0'}
    assert tfms == expected_tfms, f'Unexpected lib TFMs: {sorted(tfms)}'
    assert not any('/net9.0/' in name for name in names), 'net9.0 assets must not be packaged'

    nuspec_name = next(name for name in names if name.endswith('.nuspec'))
    root = ET.fromstring(archive.read(nuspec_name))
    metadata = root.find('n:metadata', namespace)
    assert metadata is not None
    assert metadata.findtext('n:id', namespaces=namespace) == 'Microsoft.Extensions.AI.Abstractions'
    assert metadata.findtext('n:version', namespaces=namespace) == expected_version

    groups = {
        group.attrib.get('targetFramework'): {
            dep.attrib['id']: dep.attrib.get('version')
            for dep in group.findall('n:dependency', namespace)
        }
        for group in metadata.findall('n:dependencies/n:group', namespace)
    }
    assert groups.get('.NETFramework4.6.2', {}).get('System.Text.Json') == '8.0.6', groups
    assert groups.get('.NETStandard2.0', {}).get('System.Text.Json') == '8.0.6', groups
    assert 'System.Text.Json' not in groups.get('net8.0', {}), groups

print(f'Validated {package}: net462, net8.0, netstandard2.0; no net9.0; STJ dependencies preserved.')
PY

# Smoke-test the net8.0 implementation with the .NET 8 runtime and its System.Text.Json 8.x.
# This is the asset a net9.0 consumer falls back to when this package omits net9.0.
dotnet=${JB_DOTNET:-"$fork/dotnet-sdk.cmd"}
smoke_dir=$(mktemp -d)
trap 'rm -rf "$smoke_dir"' EXIT
cp "$fork/verify/MeaiSmoke.csproj" "$fork/verify/Program.cs" "$smoke_dir/"
run_dotnet() {
  (cd /tmp && DOTNET_VERSION=8.0.408 "$dotnet" "$@")
}
run_dotnet restore "$smoke_dir/MeaiSmoke.csproj" \
  --source "$root/artifacts/jetbrains/packages" \
  --source https://api.nuget.org/v3/index.json \
  "-p:MeaiPackageVersion=$expected_version"
run_dotnet run --project "$smoke_dir/MeaiSmoke.csproj" -c Release --no-restore \
  "-p:MeaiPackageVersion=$expected_version"
