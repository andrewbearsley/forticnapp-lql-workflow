# Scripts

Small helpers. All assume `lacework`, `jq`, and `python3` on your `$PATH`,
and a working Lacework CLI profile.

## clone-policy.sh

Clones a built-in policy into editable YAML files, with the IDs rewritten
so they don't collide with the original.

```bash
./clone-policy.sh lacework-global-42

# Override the suffix used on cloned IDs (defaults to "tuned"):
CUSTOM_SUFFIX=myorg ./clone-policy.sh lacework-global-42
```

Output lands in `./cloned/<policy-id>/`. Read
[04-cloning-builtins.md](../04-cloning-builtins.md) for the full flow.

## run-local-query.sh

Run a query YAML against live data. JSON by default, CSV or plain table on
request.

```bash
./run-local-query.sh query.yaml                 # last 24h, JSON
./run-local-query.sh query.yaml "-7d"           # last 7 days
./run-local-query.sh query.yaml "-24h" csv      # CSV for spreadsheets
./run-local-query.sh query.yaml "-24h" table    # human-readable table
```

Short enough that I'd just alias it in `.zshrc` eventually, but it's
handy to have here while you're learning the CLI flags.
