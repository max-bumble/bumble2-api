#!/usr/bin/env bash
set -euo pipefail

SERVICES_FILE="${1:-swagger-services.txt}"
UI_IMAGE="${2:-swaggerapi/swagger-ui:latest}"

[[ -f "$SERVICES_FILE" ]] || { echo "::error::Services file not found: $SERVICES_FILE"; exit 1; }

rm -rf dist
mkdir -p dist/_ui

# Pull Swagger UI once
cid="$(docker create "$UI_IMAGE")"
docker cp "$cid":/usr/share/nginx/html/. dist/_ui/
docker rm -f "$cid"

# Build per service
while IFS=: read -r NAME SPEC; do
  [[ -z "${NAME:-}" || -z "${SPEC:-}" ]] && continue

  mkdir -p "dist/$NAME"
  rsync -a "dist/_ui/" "dist/$NAME/"

  # Pin to local spec (keep terminator at column 0)
  cat >"dist/$NAME/swagger-initializer.js" <<'EOF_INIT'
window.ui = SwaggerUIBundle({
  url: "openapi.yml",
  dom_id: '#swagger-ui',
  deepLinking: true,
  presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
  layout: "StandaloneLayout"
});
EOF_INIT

  # Copy spec (normalize name)
  [[ -f "$SPEC" ]] || { echo "::error::Spec not found: $SPEC"; exit 1; }
  cp "$SPEC" "dist/$NAME/openapi.yml"

  # Copy $ref-ed components if present
  SPEC_DIR="$(cd "$(dirname "$SPEC")" && pwd)"
  if [[ -d "$SPEC_DIR/components" ]]; then
    rsync -a "$SPEC_DIR/components/" "dist/$NAME/components/" 2>/dev/null || true
  fi
done < "$SERVICES_FILE"

rm -rf dist/_ui
echo "Done. Folders under dist/:"
find dist -maxdepth 1 -type d -not -path dist -printf '  %f\n' 2>/dev/null || true
