# Frameworks

A framework is a named collection of policies that rolls up into a
compliance report. CIS AWS Foundations v4, NIST 800-53, your internal
"CloudSec baseline" if you've built one. A policy only appears in a
compliance report if it's a member of at least one framework.

This is the step most people forget after cloning a built-in. The clone
exists, it's firing alerts, but the compliance percentage next to "CIS
5.2" stops moving because the report is still looking at the disabled
original.

## Viewing frameworks

```bash
# List frameworks you can see.
lacework api get /api/v2/ReportDefinitions | jq -r '.data[] | "\(.reportDefinitionGuid)  \(.reportName)"'

# Show one in detail (includes the list of member policies).
lacework api get /api/v2/ReportDefinitions/<guid> | jq
```

A gotcha: `/api/v2/ReportDefinitions` does not always list every custom
framework. Recently-added ones sometimes only show up under
`/api/v2/Reports`. If a framework seems to have vanished, try the Reports
endpoint before assuming it was deleted.

## Creating a framework

In the console: Governance, then Frameworks, then Create framework. Give
it a name, pick a cloud, tick the policies you want included.

On the command line you build a JSON payload and POST it. The shape is:

```json
{
  "reportName": "My Org CloudSec Baseline",
  "reportType": "AWS",
  "subReports": [
    {
      "domain": "AWS",
      "sections": [
        {
          "category": "IAM",
          "policies": ["custom-policy-42", "custom-policy-57"]
        },
        {
          "category": "S3",
          "policies": ["custom-policy-88"]
        }
      ]
    }
  ]
}
```

```bash
lacework api post /api/v2/ReportDefinitions --data @framework.json
```

The policy IDs are just strings. You can mix custom and built-in policies
in the same section; a framework doesn't care who owns them.

## Updating membership

Two paths, depending on what you want:

- Add a policy to an existing framework: fetch the definition, append the policy ID to the right section, `PATCH` it back.
- Swap a cloned policy in for the built-in it replaces: same fetch-edit-patch flow, but replace the entry rather than append.

```bash
# Fetch, edit in place, patch back.
lacework api get /api/v2/ReportDefinitions/<guid> > fw.json
# edit fw.json
lacework api patch /api/v2/ReportDefinitions/<guid> --data @fw.json
```

Framework updates take effect on the next report run. Depending on the
report size, that's minutes to a couple of hours.

## Pulling a report

```bash
# JSON payload with policy inventory and per-resource recommendations.
lacework api get "api/v2/Reports?format=json\
&primaryQueryId=123456789012\
&reportName=My Org CloudSec Baseline"

# For Azure you need both tenant and subscription.
lacework api get "api/v2/Reports?format=json\
&primaryQueryId=<tenant-guid>\
&secondaryQueryId=<subscription-id>\
&reportName=CIS Microsoft Azure Foundations Benchmark v4.0.0"
```

One thing that will bite you: the `START_TIME` in the report payload is
when the report ran, not when the misconfiguration was first detected.
There is no "first seen" timestamp in the Reports API, only in the
alerts stream. If you need MTTR data, get it from Alerts, not Reports.

## A practical pattern

When you clone a built-in that belonged to framework F:

1. Create the clone (`04-cloning-builtins.md`).
2. Add the clone to F as a new policy in the same section the original was in.
3. Remove the original from F.
4. Disable the original policy.
5. Wait for the next report run, confirm the section shows the same or better coverage.

Doing it in that order means there's never a moment where the control
isn't being evaluated by anything.
