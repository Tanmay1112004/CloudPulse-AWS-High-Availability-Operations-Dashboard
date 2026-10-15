# Validation and recovery evidence

Record date, region, project name, and screenshots for each test.

| Test | Method | Expected evidence |
|---|---|---|
| Local unit tests | `python3 -m unittest discover -s app -p 'test_*.py' -v` | All route tests pass |
| Terraform formatting | `terraform -chdir=terraform fmt -check -recursive` | No formatting changes required |
| Terraform validation | `terraform -chdir=terraform validate` | Configuration is valid |
| Dashboard | Open `website_url` output | Dashboard renders |
| Health | `curl -i "$URL/health/ready"` | HTTP 200 |
| Status | `curl -s "$URL/api/status"` | Instance telemetry JSON |
| Counter API | `curl -s "$URL/api/visits"` | Shared visit total without incrementing it |
| Shared counter | Refresh `/`, then inspect DynamoDB item | `visits` increases |
| Multi-AZ | Inspect EC2 instances and target health | Targets distributed across AZs |
| Recovery | Terminate one project ASG instance | Replacement instance appears and becomes healthy |
| Cleanup | Run `./cleanup.sh` and inspect AWS resources | Stack resources removed |

## Portfolio evidence to capture

1. Dashboard screenshot with the live shared total and responding instance.
2. Target group showing healthy targets in separate Availability Zones.
3. Auto Scaling group capacity settings and target-tracking policy.
4. DynamoDB `homepage` item before and after loading `/` (polling `/api/visits` should not increment it).
5. Instance replacement observation, recording instance IDs and elapsed time only if measured.
6. Terraform plan/validation and smoke-test output.
7. Cleanup completion.

`/health` is a liveness response. `/health/ready` confirms the web process can serve requests; it does not require Lambda or DynamoDB to answer because the dashboard can still serve when its optional counter dependency is unavailable. Record only results you personally observed.

Do not record a test as passed until you have observed the result. Keep screenshots free of account IDs, credentials, and other sensitive information.
