# Production-readiness roadmap

CloudPulse is a learning project, not a production deployment. This checklist orders the main improvements by the risk they address.

## 1. Secure the network edge

- Put EC2 instances in private subnets with no public IPs. Let the ALB remain public.
- Add an HTTPS listener with ACM certificates and a domain. Redirect HTTP to HTTPS.
- Choose explicit egress: NAT gateways for general outbound access, or VPC endpoints where supported and cost-effective.
- Add request throttling or AWS WAF rules if the public endpoint needs abuse protection.

## 2. Protect application and infrastructure data

- Store Terraform state in a private, versioned, encrypted S3 bucket with locking and tightly scoped access. Do not commit state or credentials.
- Review every IAM action/resource pair, including the instance role, Lambda role, and deployment identity.
- Enable DynamoDB point-in-time recovery and define retention/restore expectations.
- Set retention for application and bootstrap logs, and avoid logging secrets or sensitive request data.

## 3. Make operations actionable

- Add SNS destinations for CloudWatch alarms and test notifications.
- Add dashboards for request volume, target health, latency, errors, capacity, and Lambda/DynamoDB failures.
- Add structured request logs with request IDs and latency; consider tracing across ALB, app, Lambda, and DynamoDB.
- Define and rehearse a recovery runbook, including rollback and data restore.

## 4. Build a reviewed delivery pipeline

- Add CI that runs Python unit tests, Terraform formatting, initialization, validation, and security/static checks on every pull request.
- Produce and review a Terraform plan artifact before any apply; keep apply approval separate from code review.
- Pin provider/action versions deliberately and update them through reviewed dependency changes.
- Add a staging environment and smoke checks before production promotion.

## 5. Improve the application service

- Replace the standard-library demo server with a maintained production WSGI/ASGI server and a defined dependency lock strategy.
- Add request timeouts, graceful shutdown, bounded concurrency, and rate limiting.
- Separate configuration from code and validate required settings at startup.
- Add integration tests for Lambda counter read/increment behavior and concurrent requests; add load tests with explicit cost limits.

## Repository layout

The current project is already small and reasonably separated by responsibility:

```text
app/                 Python service and static dashboard assets
terraform/           AWS resources, variables, outputs, and Lambda source
scripts/             local deployment and smoke-test helpers
docs/                architecture, validation, interview notes, roadmap
README.md            project overview, local/AWS usage, resume summary
```

Keep generated plans, Terraform state, credentials, Python caches, and deployment ZIPs out of Git. As the app grows, split Python code into modules such as `app/routes.py`, `app/aws_counter.py`, and `app/config.py`, and move tests under `tests/`; avoid adding structure before those boundaries need to change independently.

## Suggested feature backlog

1. HTTPS, private instances, and an explicit egress strategy.
2. CI validation and a reviewed Terraform plan workflow.
3. Alarm notifications and actionable dashboards.
4. DynamoDB recovery settings and tested restore documentation.
5. Request tracing, rate limiting, and load-tested capacity targets.
