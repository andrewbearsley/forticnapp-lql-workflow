# Policy lifecycle

A policy is a query plus a bunch of metadata that controls how violations
show up in the platform: severity, remediation text, whether it's on,
which framework it belongs to, which resources are excepted from it.

## The YAML

Here's a full policy file. Most fields are self-explanatory; the ones
worth flagging are called out below.

```yaml
title: "EC2 instances must require IMDSv2"
description: "Flags EC2 instances with IMDSv1 enabled."
severity: high            # critical | high | medium | low | info
enabled: true
policyType: Violation      # Violation | Compliance
queryId: MyOrg_IMDSv2_v1
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
remediation: |-
  Modify the instance metadata options so HttpTokens is set to "required":
    aws ec2 modify-instance-metadata-options \
      --instance-id i-1234567890abcdef0 \
      --http-tokens required \
      --http-endpoint enabled
tags:
  - "domain:AWS"
  - "compliance:internal"
  - "owner:cloudsec"
alertEnabled: true
alertProfile: LW_CloudConfig_AlertProfile.CfgAws
evalFrequency: Hourly
```

Fields worth knowing:

- `queryId` is the saved query this policy runs. If the query lives elsewhere (you already created it), omit `queryText`. If you inline `queryText`, the platform will create the query for you on policy create.
- `policyType` is `Violation` for "these resources are bad" and `Compliance` for "these resources are missing a required control". They map to different alert behaviours; `Violation` is what you want most of the time.
- `severity` is a string, not a number. The spelling is literal.
- `tags` is a list of `"key:value"` strings, not a dict. The API returns it as a list and the CLI will cheerfully reject a dict.
- `alertProfile` determines what the alert payload looks like when the policy fires. `LW_CloudConfig_AlertProfile.CfgAws` is the default for AWS CSPM and works for most cases.
- `evalFrequency` is `Hourly` or `Daily`. For inventory-based policies (anything sourced from `LW_CFG_*`), evaluation is typically every 24 hours regardless. The setting is more meaningful for policies over data that arrives faster than daily, like activity logs or host-agent data.
- `policyId` should be absent on create. The platform assigns you something like `custom-policy-42`. On updates, it's required.

## Create, update, enable, disable

```bash
# Create (policy ID is assigned by the server; capture it from the output).
lacework policy create -f my-policy.yaml

# Update. The YAML must now include the policyId you were given.
lacework policy update -f my-policy.yaml

# Flip on/off without editing the file.
lacework policy enable  custom-policy-42
lacework policy disable custom-policy-42

# Show the full definition.
lacework policy show custom-policy-42
lacework policy show custom-policy-42 --yaml > snapshot.yaml

# Delete. Irreversible. Built-ins can't be deleted, only disabled.
lacework policy delete custom-policy-42
```

A couple of behaviours to be aware of:

- Disable is reversible and preserves history. Delete is not.
- Updating a policy's `queryText` updates the underlying query in place, which means historical violations are still attributed to the old logic. If you've materially changed what the policy means, you're usually better off creating a new policy and retiring the old one.
- You can't edit a built-in (`lacework-global-*`). The CLI will let you try; the API rejects it.

## Exceptions

Exceptions are how you say "this policy is correct in general, but ignore
resource X". They're separate objects attached to a policy and they're the
right tool whenever the policy logic is fine and you just need to scope it.

```bash
lacework policy-exception list custom-policy-42
lacework policy-exception create custom-policy-42 -f exception.yaml
lacework policy-exception delete custom-policy-42 <exception-id>
```

The exception YAML lets you constrain by account, resource ID, region,
resource tag, or a few other dimensions. Example:

```yaml
description: "Allow public access for marketing-site bucket (intentional)"
constraints:
  - fieldKey: accountIds
    fieldValues:
      - "123456789012"
  - fieldKey: resourceNames
    fieldValues:
      - "arn:aws:s3:::marketing-site-prod"
```

Exceptions beat cloning in almost every case where the logic is sound and
you just need carve-outs. Cloning is for when the logic itself is wrong for
your environment.

## Viewing violations

```bash
# Violations for one policy, last 24h.
lacework api get "/api/v2/Configs/ComplianceEvaluations/search" --data '{
  "timeFilter": { "startTime": "-24h" },
  "filters": [{ "expression": "eq", "field": "policyId", "value": "custom-policy-42" }]
}'

# Or eyeball it in the console under Alerts, filtered by policy.
```

## Tags I keep reaching for

- `domain:AWS` / `domain:Azure` / `domain:GCP` so the policy shows up under the right provider view.
- `compliance:<framework-id>` to signal which internal framework owns it.
- `owner:<team>` so alerts can be routed.

Tags are also the cleanest way to bulk-disable or bulk-update policies
later, because the API filters on them.
