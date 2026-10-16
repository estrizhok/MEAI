# JetBrains MEAI package build

This is a narrow fork of the `Microsoft.Extensions.AI.Abstractions` package from
`dotnet/extensions` commit `3a47559ad3eda6b4561b85c592212a9aaa892855` (the source
commit recorded in the upstream 9.10.2 package). It keeps the upstream package ID
and implementation, but deliberately omits the `net9.0` target. For a `net9.0`
consumer NuGet therefore selects the `net8.0` implementation, which does not
reference the `System.Text.Json` 9-only schema API. The `net462`, `netstandard2.0`,
and `net8.0` assets and their dependency groups remain as upstream defined them.

The package ID remains `Microsoft.Extensions.AI.Abstractions` so existing
`PackageReference`s and the MCP fork's dependency identity do not change. Fork
builds use a distinct stable four-part package version: upstream `9.10.2` becomes
`9.10.3.<JbForkRevision>`. The TeamCity build counter supplies that final part.

The net8.0 asset does not contain three net9-only `HostedMcpServerTool` members
(`Url`, `Headers` getter, and `Headers` setter). As a result, those members are
not available to consumers that resolve this fork's net8.0 asset; the package
validation suppressions document this intentional consequence of omitting the
net9.0 asset.

## Build

The JetBrains overlay is in this directory; upstream build files are otherwise
left alone apart from the project's target-framework list.

```bash
jetbrains/build.sh build -p:JbForkRevision=1
# Sign artifacts/jetbrains/bin/**/*.dll before packing in TeamCity.
jetbrains/build.sh pack -p:JbForkRevision=1
jetbrains/verify.sh 1
```

`build.sh` bootstraps the exact .NET SDK pinned by upstream `global.json`, rather
than using whatever SDK happens to be installed on the agent. It invokes the SDK
from `/tmp` so SDK selection is explicit. `CompatibilitySuppressions.xml` keeps
upstream package API validation enabled; its additional `net9.0`-to-`net8.0`
entries make the intentional asset fallback explicit.
