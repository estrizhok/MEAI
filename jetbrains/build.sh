#!/usr/bin/env bash
# Build and pack the JetBrains MEAI asset set.
# Usage: jetbrains/build.sh {build|pack|all|restore} [-p:JbForkRevision=N]
set -euo pipefail

step=${1:?expected build, pack, all or restore}
shift
fork=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$fork")
out="$root/artifacts/jetbrains"
project="$root/src/Libraries/Microsoft.Extensions.AI.Abstractions/Microsoft.Extensions.AI.Abstractions.csproj"
dotnet=${JB_DOTNET:-"$fork/dotnet-sdk.cmd"}

mkdir -p "$out"
args=(
  "-p:CustomAfterMicrosoftCommonTargets=$fork/JetBrains.Fork.targets"
  "-p:CustomAfterMicrosoftCommonCrossTargetingTargets=$fork/JetBrains.Fork.targets"
  "-p:ArtifactsDir=$out/"
)

run_dotnet() {
  # The upstream global.json pins a prerelease SDK. The JetBrains fork uses the shared, pinned stable SDK instead.
  # SDK selection is based on the working directory, so invoke the project from outside the checkout.
  (cd /tmp && "$dotnet" "$@")
}

build() {
  run_dotnet build "$project" -c Release "${args[@]}" "$@"
}

pack() {
  mkdir -p "$out/packages"
  rm -f "$out"/packages/Microsoft.Extensions.AI.Abstractions.*.nupkg
  run_dotnet pack "$project" -c Release --no-build --no-restore -o "$out/packages" "${args[@]}" "$@"
}

case "$step" in
  build)   build "$@" ;;
  pack)    pack "$@" ;;
  all)     build "$@"; pack "$@" ;;
  restore) run_dotnet restore "$project" "${args[@]}" "$@" ;;
  *)       echo "Unknown step '$step'; expected build, pack, all or restore." >&2; exit 2 ;;
esac
