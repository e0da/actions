# shellcheck shell=sh disable=SC2154
release_exists=false
if gh release view "$DESTINATION_TAG" >/dev/null 2>&1; then
  release_exists=true
  existing_release_dir=.existing-release-assets
  mkdir "$existing_release_dir"
  existing_asset_names=$(gh release view "$DESTINATION_TAG" --json assets --jq '.assets[].name')
  for asset in "$archive" "$checksum"; do
    if printf '%s\n' "$existing_asset_names" | grep -Fx "$asset" >/dev/null; then
      gh release download "$DESTINATION_TAG" --pattern "$asset" --dir "$existing_release_dir"
      if ! cmp -s "$asset" "$existing_release_dir/$asset"; then
        echo "release asset differs from the existing immutable asset: $asset" >&2
        exit 1
      fi
    else
      gh release upload "$DESTINATION_TAG" "$asset"
    fi
  done
  echo "release assets are complete and existing bytes remain immutable"
fi
