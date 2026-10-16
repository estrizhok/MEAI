#!/usr/bin/env bash
# Verify the package assets/dependency groups and exercise its net8.0 implementation with System.Text.Json 8.x.
set -euo pipefail
fork=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$fork")
revision=${1:-1}
package_dir="$root/artifacts/jetbrains/packages"

# Find the single package from this TeamCity build by its metadata and final revision component;
# neither the upstream version nor the package filename is duplicated here.
readarray -t package_info < <(python3 - "$package_dir" "$revision" <<'PY'
import glob
import os
import sys
import zipfile
import xml.etree.ElementTree as ET

package_dir, revision = sys.argv[1:]
namespace = {'n': 'http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd'}
matches = []
for package in glob.glob(os.path.join(package_dir, 'Microsoft.Extensions.AI.Abstractions.*.nupkg')):
    if package.endswith('.symbols.nupkg'):
        continue
    with zipfile.ZipFile(package) as archive:
        nuspec = next(name for name in archive.namelist() if name.endswith('.nuspec'))
        root = ET.fromstring(archive.read(nuspec))
        metadata = root.find('n:metadata', namespace)
        if metadata is None or metadata.findtext('n:id', namespaces=namespace) != 'Microsoft.Extensions.AI.Abstractions':
            continue
        version = metadata.findtext('n:version', namespaces=namespace)
        components = version.split('.') if version else []
        if len(components) == 4 and components[-1] == revision and all(component.isdigit() for component in components):
            matches.append((package, version))

assert len(matches) == 1, f'Expected one package with fork revision {revision}, found {matches}'
print(matches[0][0])
print(matches[0][1])
PY
)
package=${package_info[0]}
package_version=${package_info[1]}

python3 - "$package" "$package_version" <<'PY'
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

# This is the asset a net9.0 consumer falls back to when the package omits net9.0.
dotnet=${JB_DOTNET:-"$fork/dotnet-sdk.cmd"}
smoke_dir=$(mktemp -d)
trap 'rm -rf "$smoke_dir"' EXIT
cp "$fork/verify/MeaiSmoke.csproj" "$fork/verify/Program.cs" "$smoke_dir/"
run_dotnet() {
  (cd /tmp && DOTNET_VERSION=8.0.408 "$dotnet" "$@")
}
run_dotnet restore "$smoke_dir/MeaiSmoke.csproj" \
  --source "$package_dir" \
  --source https://api.nuget.org/v3/index.json \
  "-p:MeaiPackageVersion=$package_version"
run_dotnet run --project "$smoke_dir/MeaiSmoke.csproj" -c Release --no-restore \
  "-p:MeaiPackageVersion=$package_version"
