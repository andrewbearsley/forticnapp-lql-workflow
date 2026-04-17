# Examples

Three policies covering the patterns you'll use most often. All start
disabled so you can create them in a lab account without surprising
anybody.

| File | Pattern | What it flags |
| ---- | ------- | ------------- |
| [aws-imdsv2-required.yaml](aws-imdsv2-required.yaml) | Resource-level filter | EC2 instances not enforcing IMDSv2 |
| [aws-sg-ssh-open-to-world.yaml](aws-sg-ssh-open-to-world.yaml) | Array iteration with `array_to_rows` | Security groups allowing 0.0.0.0/0 on port 22 |
| [aws-account-missing-security-contact.yaml](aws-account-missing-security-contact.yaml) | Account-level NOT IN subquery | Accounts missing a SECURITY alternate contact |

Run any of them against live data before creating:

```bash
lacework query run -f examples/aws-imdsv2-required.yaml --start "-24h" --json
```

Then create the policy (still disabled because `enabled: false`):

```bash
lacework policy create -f examples/aws-imdsv2-required.yaml
```

Enable when you're ready:

```bash
lacework policy enable <policy-id>
```
