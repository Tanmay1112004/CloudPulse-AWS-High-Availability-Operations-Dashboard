# Interview notes: CloudPulse

## Explain the project in 45 seconds

I built CloudPulse, a small AWS operations dashboard provisioned with Terraform. An internet-facing Application Load Balancer routes traffic to a Python service on EC2 instances in two Availability Zones, managed by an Auto Scaling group. The service reports instance telemetry and health endpoints. Homepage requests increment a shared DynamoDB counter through Lambda; a separate read-only endpoint refreshes the dashboard total without counting the poll as another visit. The application artifact is stored in private S3, and instances use an IAM role rather than embedded AWS keys. The project also includes deployment smoke checks, CloudWatch logs and alarms, recovery guidance, and teardown instructions.

## Common questions

**Why an Application Load Balancer?** It provides a stable HTTP entry point, distributes requests to healthy targets, and supports application-level health checks.

**Why use two Availability Zones?** It reduces dependence on one zone. It does not guarantee zero downtime; capacity, health checks, and the recovery behavior must be validated.

**What is the difference between liveness and readiness here?** `/health` confirms the process responds. `/health/ready` confirms the web process can serve dashboard traffic. Lambda and DynamoDB are optional for serving the page, so readiness does not fail when the counter is unavailable.

**How is the page-request counter safe across instances?** The app invokes Lambda, which uses DynamoDB's atomic `ADD` update. The app does not perform a read-then-write increment. `/api/visits` uses a read action and does not increment the total.

**Why does the local counter reset?** Local mode stores it in process memory. The deployed shared total is in DynamoDB and survives individual instance replacement while the table exists.

**How does Auto Scaling replace a failed target?** The ASG uses ELB health checks. If an instance remains unhealthy, the group can replace it. I would confirm that behavior with target health and ASG activity history instead of assuming recovery time.

**Why is there no SSH ingress?** The instance security group accepts application traffic only from the ALB. Systems Manager is provided for managed access when its IAM and network requirements are met.

**How would you harden this for production?** Add HTTPS and a domain, move application instances into private subnets, choose controlled egress or VPC endpoints, use remote encrypted Terraform state with locking, review IAM policies, add CI plan review, and configure alert destinations and a tested recovery plan.

**Does the dashboard show AWS control-plane health?** No. It displays application-reported telemetry. The AWS console or APIs remain the source for target health, ASG events, and infrastructure state.

## Troubleshooting approach

| Symptom | First checks |
|---|---|
| ALB returns 503 | Target health reason, `/health/ready`, systemd service status, listener/target port, and instance security group source |
| Targets remain unhealthy | Confirm the service binds to `0.0.0.0:8080`, inspect cloud-init and systemd logs, verify the health path and port |
| Dashboard loads but counter is unavailable | Lambda logs, EC2 role invoke permission, function-name environment variable, Lambda `GetItem`/`UpdateItem` permissions, and DynamoDB table |
| Instance cannot fetch its artifact | Instance role S3 object scope, bucket/key, route connectivity, and cloud-init output |
| Terraform access denied | Check AWS caller identity, region, IAM permissions, service quotas, and the failed resource action |

Only report deployment, failover, or recovery measurements you personally observed. The project is an educational HTTP lab, not a production security baseline.
