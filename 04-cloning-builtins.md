# Cloning built-in policies

The built-in policies (anything prefixed `lacework-global-`) are read-only.
You can disable them, you can add exceptions, you can change severity. You
cannot change the query. Sooner or later somebody will ask for a check
that's "like policy X but with this extra condition", and you have to clone.

## Decide first: exception, or clone?

Before cloning, check whether an exception will do the job. Exceptions are
cheaper to live with: they stay scoped to the original policy, so when
Lacework ships a better version of that check you inherit the improvement.
A cloned policy is yours to maintain forever.

Use an exception when:

- The policy logic is right; you just need to exclude a handful of resources.
- You want a temporary carve-out (e.g. while a fix is in progress).
- The exclusion fits the available constraint fields (account ID, resource ID, resource name, tags, region).

Clone when:

- The threshold is wrong for your environment (e.g. a policy flags any IAM key older than 90 days and you want 45).
- The logic misses cases that matter to you.
- You want a different severity applied dynamically based on the query output, not a flat severity for the whole policy.
- You need to add a cross-resource join that the built-in didn't do.

## The clone workflow

Three files, three commands, one disable. The `clone-policy.sh` script
under `scripts/` does the boring parts.

```bash
./scripts/clone-policy.sh lacework-global-42
```

It writes four files into `cloned/lacework-global-42/`:

```
original-policy.yaml   # what you fetched, untouched, for reference
original-query.yaml    # same
policy.yaml            # rewritten clone of the policy, ready to edit
query.yaml             # rewritten clone of the query, ready to edit
```

The rewrite strips server-assigned fields (`policyId`, `owner`,
`lastUpdateTime`, and friends), renames `queryId` so it doesn't collide
with the built-in, and tacks a "(cloned from lacework-global-42)" note
onto the description so future-you knows where it came from.

## Edit the query

Open `cloned/lacework-global-42/query.yaml`, change the filter, save. Then
run it against live data before you commit to saving it:

```bash
lacework query run -f cloned/lacework-global-42/query.yaml --start "-24h" --json | jq 'length'
```

Compare row count and the actual rowset against the original. Row count
alone will lie to you; a clone can easily return the same number of rows
with different resources in them. Diff the resource IDs.

```bash
# The built-in's current violations:
lacework api get "/api/v2/Configs/ComplianceEvaluations/search" --data '{
  "timeFilter": { "startTime": "-24h" },
  "filters": [{ "expression": "eq", "field": "policyId", "value": "lacework-global-42" }]
}' | jq '[.data[].resource] | sort | unique'

# Your clone's output:
lacework query run -f cloned/lacework-global-42/query.yaml --start "-24h" --json \
  | jq '[.[] | .RESOURCE_KEY] | sort | unique'
```

If the diff is "my clone flags everything the original flagged, plus these
new ones I expected to flag, and nothing I didn't expect", you're done.

## Promote it

```bash
# Save the query.
lacework query create -f cloned/lacework-global-42/query.yaml

# Save the policy. It starts disabled if you set enabled: false, which is
# usually what you want so you can sanity-check it in the UI first.
lacework policy create -f cloned/lacework-global-42/policy.yaml
```

Grab the new policy ID from the create output (it'll look like
`custom-policy-42`). Open the console, find the policy, confirm severity,
title, remediation text, and tags look right.

## Retire the original

Once the clone is doing its job:

```bash
lacework policy disable lacework-global-42
```

If the original was in a compliance framework, your clone doesn't inherit
that membership. You either swap the clone in (see `05-frameworks.md`), or
accept that the control is now reported through your custom framework
instead of the Lacework-provided one. Don't forget this step; it's the
most common way for a clone project to quietly leave a gap in reporting.

## Drift detection

Lacework updates built-in policies occasionally. If you've cloned one, you
should know when the upstream version changes so you can decide whether to
pull the change into your clone.

Cheap version: store the `original-query.yaml` in git, diff against
`lacework query show <original-query-id> --yaml` on a schedule, open an
issue when it changes.

```bash
# In a cron / CI job
diff <(lacework query show LW_LQL_EC2_IMDSv2 --yaml) \
     ./cloned/lacework-global-42/original-query.yaml \
  || echo "upstream changed, review"
```

Not glamorous. Effective.

## Bulk cloning

If you're replacing a whole framework's worth of built-ins, loop over the
policy IDs:

```bash
for id in $(cat policies-to-clone.txt); do
  ./scripts/clone-policy.sh "$id"
done
```
