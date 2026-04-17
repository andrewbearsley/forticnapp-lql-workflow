#!/usr/bin/env bash
# Clone a Lacework-provided policy into a custom one you can edit, then
# disable the original. Run with the built-in policy ID as the only argument.
#
#   ./clone-policy.sh lacework-global-42
#
# Output: two YAML files in ./cloned/<policy-id>/
#   - query.yaml   (the LQL query, renamed so it doesn't collide)
#   - policy.yaml  (the policy, pointing at the new query)
#
# Neither file is uploaded. Review, tweak, then run the "create" block
# printed at the end.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <builtin-policy-id>   e.g. lacework-global-42" >&2
  exit 1
fi

ORIGINAL_ID="$1"
SUFFIX="${CUSTOM_SUFFIX:-tuned}"          # override with: CUSTOM_SUFFIX=myorg ./clone-policy.sh ...
OUTDIR="./cloned/${ORIGINAL_ID}"
mkdir -p "$OUTDIR"

echo "Fetching ${ORIGINAL_ID}..."
lacework policy show "$ORIGINAL_ID" --yaml > "$OUTDIR/original-policy.yaml"

# Pull the query ID the policy points at, then grab the query itself.
ORIGINAL_QUERY_ID=$(grep -E '^queryId:' "$OUTDIR/original-policy.yaml" | awk '{print $2}' | tr -d '"')
if [[ -z "$ORIGINAL_QUERY_ID" ]]; then
  echo "could not find queryId in $OUTDIR/original-policy.yaml" >&2
  exit 1
fi

echo "Fetching query ${ORIGINAL_QUERY_ID}..."
lacework query show "$ORIGINAL_QUERY_ID" --yaml > "$OUTDIR/original-query.yaml"

# New IDs. Keep the original in the name so you can trace it back later.
NEW_QUERY_ID="${ORIGINAL_QUERY_ID}_${SUFFIX}"
NEW_POLICY_ID_HINT="${ORIGINAL_ID#lacework-global-}_${SUFFIX}"    # Lacework assigns the real ID on create

# Rewrite the query: swap the ID, drop server-side fields.
sed -E \
  -e "s/^queryId:.*/queryId: ${NEW_QUERY_ID}/" \
  -e '/^(owner|lastUpdateUser|lastUpdateTime|resultSchema):/d' \
  "$OUTDIR/original-query.yaml" > "$OUTDIR/query.yaml"

# Rewrite the policy: point at the new query, clear server-assigned fields,
# add a note so future-you knows where it came from.
sed -E \
  -e "s/^queryId:.*/queryId: ${NEW_QUERY_ID}/" \
  -e '/^(policyId|policyType|owner|lastUpdateUser|lastUpdateTime|evaluatorId):/d' \
  "$OUTDIR/original-policy.yaml" > "$OUTDIR/policy.yaml"

# Tack the provenance onto the description so it surfaces in the UI.
python3 - "$OUTDIR/policy.yaml" "$ORIGINAL_ID" <<'PY'
import sys, re, pathlib
path, original = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()
note = f" (cloned from {original})"
text = re.sub(
    r'^(description:\s*["\']?)(.*?)(["\']?)$',
    lambda m: f"{m.group(1)}{m.group(2)}{note}{m.group(3)}",
    text, count=1, flags=re.MULTILINE,
)
pathlib.Path(path).write_text(text)
PY

cat <<EOF

Wrote:
  $OUTDIR/query.yaml     (new query, id: ${NEW_QUERY_ID})
  $OUTDIR/policy.yaml    (new policy, will be assigned id like: custom-policy-${NEW_POLICY_ID_HINT})

Next steps, once you've edited the logic:

  lacework query create  -f $OUTDIR/query.yaml
  lacework policy create -f $OUTDIR/policy.yaml
  lacework policy disable ${ORIGINAL_ID}

Verify the clone is producing what you want before disabling the original:

  lacework query run -f $OUTDIR/query.yaml --start "-24h"

EOF
