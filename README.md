# Quickstart for working with FortiCNAPP policies

A working reference for people tuning FortiCNAPP (Lacework) policies. Not a
course, not exhaustive documentation. Just the handful of commands, patterns
and gotchas that come up every time you sit down to write or fix an LQL
policy, in roughly the order you need them.

Who this is for: you've opened a built-in policy, seen something you want to
change, and realised you can't edit it. Or you've been asked to add a check
that doesn't ship out of the box. Or the security team wants a custom
framework. That kind of thing.

## Quickstart

Install the CLI and point it at your account. See the official
<a href="https://docs.fortinet.com/document/forticnapp/latest/cli-reference/68020/get-started-with-the-lacework-forticnapp-cli" target="_blank">Get Started with the Lacework FortiCNAPP CLI</a>
docs for all platforms. The short version:

```bash
# macOS (Homebrew)
brew install lacework/tap/lacework-cli

# Linux
curl https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.sh | bash

# Windows (PowerShell)
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.ps1'))
```

```bash
lacework configure      # prompts for account, API key, secret
lacework policy list    # should return a few hundred policies
```

Copy a built-in policy and make it yours.

### Step 1. Clone the built-in

Pull the built-in's query + policy YAML into `cloned/` so you have something
to edit. Built-ins themselves can't be modified. This gives you a copy.

```bash
./scripts/clone-policy.sh lacework-global-42
```

### Step 2. Edit the query

Change the logic. The policy YAML usually only needs its `queryId` updated
to point at your new query; leave the rest alone at first.

```bash
$EDITOR cloned/lacework-global-42/query.yaml
```

### Step 3. Run the query against live data

Fast feedback loop, no platform state changed. Iterate here until the
rowset looks right.

```bash
lacework query run -f cloned/lacework-global-42/query.yaml --start "-24h"
```

### Step 4. Save the query

Required before a policy can reference it.

```bash
lacework query create -f cloned/lacework-global-42/query.yaml
```

### Step 5. Create the policy

Wraps the query. The platform assigns a custom ID (e.g. `custom-policy-123`).
You don't pick it.

```bash
lacework policy create -f cloned/lacework-global-42/policy.yaml
```

### Step 6. Disable the original built-in

So you're not alerting twice on the same thing. The built-in stays in the
account, just muted.

```bash
lacework policy disable lacework-global-42
```

That's the whole loop. The rest of the repo is context for each of those
steps.

## Contents

| File | What's in it |
| ---- | ------------ |
| [01-writing-lql.md](01-writing-lql.md) | LQL syntax, datasources, the five or six patterns you'll reach for constantly |
| [02-testing-queries.md](02-testing-queries.md) | How to test queries against live data without waiting on a scheduled run |
| [03-policy-lifecycle.md](03-policy-lifecycle.md) | Policy YAML anatomy, exceptions, enable/disable, updating |
| [04-cloning-builtins.md](04-cloning-builtins.md) | When to clone (vs. use an exception) and how to do it cleanly |
| [05-frameworks.md](05-frameworks.md) | Getting your custom policy to show up in compliance reports |
| [examples/](examples/) | Three policies you can `lacework policy create -f` and learn from |
| [scripts/](scripts/) | `clone-policy.sh` and a couple of helpers |

## A few things worth knowing up front

You cannot edit a built-in policy's query. You can disable it, you can add
exceptions to it, and you can change its severity. If you want different
logic, you have to clone. That is what this repo is mostly about.

Before you clone, check whether an exception would do the job. If a policy
is firing on resources you've intentionally made that way (public S3
buckets tagged `public=true`, EC2 instances tagged `imdsv1-ok=true`,
accounts owned by a team you don't cover), you can attach an exception
instead of modifying the policy. Exceptions can be added via the console
or the CLI (`lacework policy-exception create`) against built-in and
custom policies alike, and they support constraints by account, resource
ID, region, and resource tag. Clone only when the policy's underlying
logic is wrong for your environment. See
[03-policy-lifecycle.md](03-policy-lifecycle.md#exceptions) for the YAML.

Queries run on demand. There is no 24-hour wait. The confusing part is that
once a query is wrapped in a policy, the policy runs on the platform's own
schedule. Inventory-based policies are typically evaluated every 24 hours,
which matches the cadence at which cloud configuration data is collected.
So iterate on the query first, promote to a policy when the rowset looks
right.

Custom policies get their own ID prefix when you create them. You don't
pick the ID. You pick a reasonable `queryId` for the query the policy
points at, and the platform generates a policy ID like
`custom-policy-123` on create.

Scripts assume a working `lacework` CLI, `jq`, and `python3` on your `$PATH`.
They don't hold your hand with argument validation beyond what's useful.
