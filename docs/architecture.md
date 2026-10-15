# Architecture and design notes

## Request flow
1. Browser sends `GET /` to the ALB.
2. ALB forwards to a healthy EC2 target.
3. App invokes the counter Lambda synchronously when deployed with a counter function configured; local mode uses a thread-safe in-memory counter.
4. Lambda atomically adds one to the `homepage` DynamoDB item.
5. App returns dashboard HTML with the counter value. A counter dependency error is shown in the dashboard and does not take the web process down.
6. Browser polls `/api/status` every five seconds for instance telemetry and `/api/visits` every ten seconds for the shared total. Neither polling route increments the shared counter.

The Lambda execution role has `UpdateItem` for increments and `GetItem` for dashboard reads. The EC2 role can invoke only this counter function.

## Availability
- ALB spans two public subnets in separate available AZs.
- Auto Scaling maintains the desired capacity and uses ELB health checks.
- Terminating a project instance should trigger replacement; validate in the EC2 and Target Groups consoles.

## Security notes
- ALB permits public HTTP for this lab; do not use for sensitive production traffic.
- Instance ingress is restricted to the ALB security group on TCP 8080.
- EC2 metadata requires IMDSv2.
- EC2 uses an instance profile rather than hard-coded AWS credentials.
- S3 public access is blocked and server-side encryption is enabled.
- IAM policies should be reviewed and narrowed further before production use.

## Operational limitations
- This demo does not provide exactly-once unique visitor counting.
- Dashboard instance telemetry is application-reported and is not a substitute for AWS control-plane health.
- `/health` is a process liveness check. `/health/ready` indicates the web process can serve traffic; it does not probe Lambda or DynamoDB because those services are optional for serving the dashboard.
- Alarm resources are created, but no SNS notification destination is configured.
- Bootstrap installs OS packages at launch, so external package repository access is required.
