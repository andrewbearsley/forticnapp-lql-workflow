# Testing queries

The most common question people ask when they start writing LQL is "do I
have to wait 24 hours for my policy to run?". No. That confusion comes from
mixing up two things: queries (runnable on demand, any time) and policies
(run on the platform's own schedule). You iterate on the query first, then
wrap it in a policy once you're happy.

Three ways to run a query against live data.

## Query Builder (web console)

Fastest for tight iteration.

1. Governance, then Policies, then Add policy.
2. Pick Compliance or Violation.
3. Drop into the Query Builder and paste or build your LQL.
4. Hit Preview Results. Rows come back in a few seconds.
5. Save when you're happy. If you're not saving yet, just close the tab; nothing persists.

The builder has schema awareness, so it will autocomplete field names once
you've chosen a datasource. Useful when you don't remember whether it's
`RESOURCE_CONFIG:IpPermissions` or `IpPermissionsEgress`.

## CLI

Useful when you're iterating from a local YAML file or want the output in a
scriptable format.

```bash
# Run a query file against the last 24 hours of data.
lacework query run -f query.yaml --start "-24h" --json

# Look at a datasource's schema or a few sample rows before writing anything.
lacework query show-source LW_CFG_AWS_EC2_INSTANCES --json
lacework query preview-source LW_CFG_AWS_EC2_INSTANCES --json | jq '.[0]'

# Heredoc, no file at all. Good for throwaway probes.
cat <<'EOF' | lacework query run --start "-24h" --json
{
  "queryText": "{ source { LW_CFG_AWS_ACCOUNTS } return { ACCOUNT_ID, ACCOUNT_ALIAS } }"
}
EOF
```

There's a small helper at `scripts/run-local-query.sh` that wraps the common
case and will also spit CSV if you want to eyeball results in a spreadsheet.

The query YAML format, for reference:

```yaml
queryId: MyQuery_v1
queryText: |-
  {
    source {
      LW_CFG_AWS_EC2_INSTANCES instance
    }
    filter {
      instance.RESOURCE_CONFIG:MetadataOptions.HttpTokens <> 'required'
    }
    return distinct {
      instance.ACCOUNT_ID,
      instance.RESOURCE_ID as RESOURCE_KEY,
      instance.RESOURCE_REGION,
      instance.RESOURCE_TYPE,
      instance.SERVICE,
      'IMDSv2NotEnforced' as COMPLIANCE_FAILURE_REASON
    }
  }
```

## API

If you want to run a query from code, or from a CI job that doesn't have
the CLI installed, hit the Queries endpoint directly.

```bash
# Ad-hoc: send the query text, get results.
lacework api post /api/v2/Queries/execute --data '{
  "queryText": "{ source { LW_CFG_AWS_EC2_INSTANCES } return { ACCOUNT_ID } }"
}'

# Saved query: just the ID.
lacework api post /api/v2/Queries/MyQuery_v1/execute
```

Results come back synchronously. There's no job polling, no webhook.

## Once it's a policy

After you promote the query to a policy, it evaluates on its own schedule.

- CSPM / config policies re-evaluate when the underlying inventory refreshes. That's roughly hourly for most datasources, less often for some of the slower APIs (CloudTrail event selectors, for example). Not 24 hours. Not instant either.
- Composite and behaviour policies are event-driven, so latency depends on the upstream event source.
- Policy history shows you each evaluation and which resources violated. If you've just created the policy and nothing's there yet, give it one full evaluation cycle before assuming it's broken.

You can force a fresh config scan with `lacework compliance aws scan`, which
triggers inventory collection across all integrated AWS accounts. Only one
scan runs at a time and they take an hour or two. Don't use this as a fast
feedback loop; use `lacework query run` instead.

## A workflow that doesn't waste your time

1. `lacework query preview-source` on the datasource you think you need. Confirm the fields actually look the way you expect.
2. Write the query in a local YAML. Run it with `lacework query run -f`. Tune until the rowset matches what you'd flag as a violation.
3. Only now, wrap it in a policy YAML. Create it disabled.
4. Run `lacework policy show <id>` to sanity-check it saved with the right severity, description, tags.
5. Enable. Watch the next evaluation cycle. Adjust.
