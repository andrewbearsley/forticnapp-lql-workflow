# Writing LQL

LQL is SQL-shaped but not SQL. If you squint at it the right way, a query is
three blocks: where the rows come from, which ones you keep, and what you
return.

```
{
  source {
    DATASOURCE alias
  }
  filter {
    <conditions>
  }
  return distinct {
    <fields>
  }
}
```

## Syntax gotchas

These are the ones that catch people every time.

- Not-equal is `<>`, not `!=`. LQL will reject `!=` with a parse error.
- Strings are single-quoted: `'required'`, never `"required"`.
- JSON/variant access uses `:` to enter the variant, then `.` to navigate inside it: `RESOURCE_CONFIG:MetadataOptions.HttpTokens`. Getting this backwards is a common mistake.
- Null checks are `IS NULL` and `IS NOT NULL`.
- Boolean operators are `AND`, `OR`, `NOT` (case-insensitive, but matching the keywords is kinder to the eye).
- Subqueries go inside `IN { source { ... } filter { ... } return distinct { ... } }`.

## Datasources

Everything is keyed on a datasource name. Names follow a prefix convention
that tells you where the rows come from:

| Prefix | What's in it |
| ------ | ------------ |
| `LW_CFG_*` | Cloud resource configuration (CSPM inventory). What most policies want. |
| `LW_HE_*` | Host examination: agentless disk scan results (packages, processes, files, containers, images). |
| `LW_HA_*` | Host agent activity from the Lacework agent (connections, process starts, file changes). |
| `LW_CE_*` | Cloud entitlement / identity data. |
| `LW_APA_*` | Attack-path analysis. |

Most policies you'll write are `LW_CFG_*`. The authoritative list lives in the
<a href="https://docs.fortinet.com/document/forticnapp/latest/lql-reference/771173/datasource-metadata" target="_blank">Datasource Metadata docs</a>,
but the fastest way to find what you need is to ask the CLI:

```bash
lacework query list-sources --json | jq -r '.[].name' | grep -i ec2
lacework query show-source LW_CFG_AWS_EC2_INSTANCES --json        # fields
lacework query preview-source LW_CFG_AWS_EC2_INSTANCES --json     # sample rows
```

### AWS config (`LW_CFG_AWS_*`)

| Service | Datasource |
| ------- | ---------- |
| Accounts | `LW_CFG_AWS_ACCOUNTS` |
| EC2 instances | `LW_CFG_AWS_EC2_INSTANCES` |
| Security groups | `LW_CFG_AWS_EC2_SECURITY_GROUPS` |
| EBS volumes | `LW_CFG_AWS_EC2_VOLUMES` |
| S3 | `LW_CFG_AWS_S3`, plus `LW_CFG_AWS_S3_GET_*` for per-bucket detail |
| IAM | `LW_CFG_AWS_IAM_USERS`, `LW_CFG_AWS_IAM_ROLES`, `LW_CFG_AWS_IAM_POLICIES` |
| Lambda | `LW_CFG_AWS_LAMBDA` |
| RDS | `LW_CFG_AWS_RDS_DB_INSTANCES` |
| CloudTrail | `LW_CFG_AWS_CLOUDTRAIL`, plus `LW_CFG_AWS_CLOUDTRAIL_GET_*` |

### Azure and GCP config

Same pattern, different middle segment. Confirm exact names with
`list-sources`; the common ones look like:

- `LW_CFG_AZURE_NETWORK_NETWORKSECURITYGROUPS`, `LW_CFG_AZURE_COMPUTE_VIRTUALMACHINES`, `LW_CFG_AZURE_STORAGE_STORAGEACCOUNTS`, `LW_CFG_AZURE_AUTHORIZATION_ROLEASSIGNMENTS`
- `LW_CFG_GCP_COMPUTE_FIREWALL`, `LW_CFG_GCP_COMPUTE_INSTANCES`, `LW_CFG_GCP_STORAGE_BUCKETS`, `LW_CFG_GCP_IAM_SERVICEACCOUNTS`

### Kubernetes and activity data

Kubernetes config and audit-log data are covered under the same umbrella but
aren't always under `LW_CFG_`. CloudTrail, Azure activity, GCP activity and
K8s audit logs are ingested for violation/behavioral policies. If you're
writing a CSPM-shaped policy, you're almost certainly staying in `LW_CFG_`.
Discover names with `list-sources` rather than guessing:

```bash
lacework query list-sources --json | jq -r '.[].name' | grep -iE 'k8s|kube'
lacework query list-sources --json | jq -r '.[].name' | grep -iE 'audit|activity|cloudtrail'
```

## Fields a compliance policy should return

If you want the policy to behave like the built-ins (show up in reports,
group by account and region, explain why it failed), return these:

```
return distinct {
  ACCOUNT_ID,
  RESOURCE_ID as RESOURCE_KEY,
  RESOURCE_REGION,
  RESOURCE_TYPE,
  SERVICE,
  'SomeShortReasonCode' as COMPLIANCE_FAILURE_REASON
}
```

For account-level checks, use `ACCOUNT_ID as RESOURCE_KEY` instead.

## Patterns worth memorising

### 1. Resource-level filter

The simplest shape. "Find resources where X is wrong."

```
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

### 2. Account-level "NOT IN" subquery

For "which accounts are missing X". You list all accounts in the outer
source and subtract the ones that have the thing.

```
{
  source {
    LW_CFG_AWS_ACCOUNTS account
  }
  filter {
    not (account.ACCOUNT_ID in {
      source {
        LW_CFG_AWS_ACCOUNT_GET_ALTERNATE_CONTACT
      }
      filter {
        RESOURCE_CONFIG:AlternateContact.AlternateContactType = 'SECURITY'
        AND RESOURCE_CONFIG:AlternateContact.Name is not null
      }
      return distinct { ACCOUNT_ID }
    })
  }
  return distinct {
    account.ACCOUNT_ID,
    account.ACCOUNT_ID as RESOURCE_KEY,
    account.RESOURCE_REGION,
    account.RESOURCE_TYPE,
    account.SERVICE,
    'SecurityContactMissing' as COMPLIANCE_FAILURE_REASON
  }
}
```

### 3. Iterating arrays

Security group rules, IAM policy statements, bucket policies, all of these
are arrays inside `RESOURCE_CONFIG`. You unroll them with
`array_to_rows()`. `value_exists` is the "any element matches" predicate.

```
{
  source {
    LW_CFG_AWS_EC2_SECURITY_GROUPS sg
  }
  filter {
    value_exists(
      array_to_rows(sg.RESOURCE_CONFIG:IpPermissions),
      ip,
      value_exists(
        array_to_rows(ip:IpRanges),
        range,
        range:CidrIp = '0.0.0.0/0'
      )
      AND ip:FromPort <= 22
      AND ip:ToPort   >= 22
    )
  }
  return distinct {
    sg.ACCOUNT_ID,
    sg.RESOURCE_ID as RESOURCE_KEY,
    sg.RESOURCE_REGION,
    sg.RESOURCE_TYPE,
    sg.SERVICE,
    'SSHOpenToWorld' as COMPLIANCE_FAILURE_REASON
  }
}
```

### 4. Joining related datasources with `with`

Some resources only make sense alongside a companion datasource. Use `with`
to pull them together. Lacework auto-joins on `RESOURCE_ID` / `ACCOUNT_ID`
for you.

```
source {
  LW_CFG_AWS_CLOUDTRAIL trail
  with LW_CFG_AWS_CLOUDTRAIL_GET_EVENT_SELECTORS selectors,
       array_to_rows(selectors.RESOURCE_CONFIG:EventSelectors) as (event_selectors)
}
filter {
  trail.RESOURCE_CONFIG:IsMultiRegionTrail = true
  and event_selectors:ReadWriteType = 'All'
  and event_selectors:IncludeManagementEvents = true
}
```

### 5. Empty config vs. missing resource

The distinction trips people up. If a companion datasource returns
`RESOURCE_CONFIG = '{}'`, the thing exists but has no configuration (e.g.
the bucket exists but has no logging config). If the subquery returns no
rows for that ID, the thing does not exist at all.

```
filter {
  bucket.RESOURCE_CONFIG = '{}'
}
```

## Reference

- <a href="https://docs.fortinet.com/document/forticnapp/latest/lql-reference" target="_blank">LQL Reference</a>: syntax, operators, functions
- <a href="https://docs.fortinet.com/document/forticnapp/latest/lql-reference/771173/datasource-metadata" target="_blank">Datasource Metadata</a>: the full list of `LW_*` datasources
- <a href="https://docs.fortinet.com/document/forticnapp/latest/cli-reference/93842/lacework-policy" target="_blank">`lacework policy` CLI reference</a>
