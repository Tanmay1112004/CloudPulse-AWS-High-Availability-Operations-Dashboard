data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  app_bundle_path = "${path.module}/app-bundle.zip"
  common_name     = substr(var.project_name, 0, 21)
}

resource "aws_vpc" "app" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.app.id
  cidr_block              = cidrsubnet(aws_vpc.app.cidr_block, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Public HTTP ingress for the educational dashboard."
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "Public HTTP; use HTTPS before production."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "instance" {
  name_prefix = "${var.project_name}-app-"
  description = "Only the ALB can reach the application port."
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "Application traffic from ALB only."
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-instance-sg" }
}

resource "aws_s3_bucket" "artifact" {
  bucket_prefix = "${var.project_name}-artifact-"
  force_destroy = true
  tags           = { Name = "${var.project_name}-artifact" }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket                  = aws_s3_bucket.artifact.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact" {
  bucket = aws_s3_bucket.artifact.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = local.app_bundle_path
  excludes    = ["__pycache__", "*.pyc", "test_server.py"]
}

resource "aws_s3_object" "app" {
  bucket      = aws_s3_bucket.artifact.id
  key         = "releases/${data.archive_file.app.output_md5}/app-bundle.zip"
  source      = data.archive_file.app.output_path
  source_hash = data.archive_file.app.output_md5
  depends_on  = [aws_s3_bucket_server_side_encryption_configuration.artifact]
}

resource "aws_dynamodb_table" "visits" {
  name         = "${var.project_name}-visits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "counter_id"

  attribute {
    name = "counter_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.project_name}-visits" }
}

resource "aws_iam_role" "lambda" {
  name_prefix = "${var.project_name}-counter-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-counter-policy"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.visits.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda-package.zip"
}

resource "aws_lambda_function" "counter" {
  function_name    = "${var.project_name}-counter"
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 5

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visits.name
    }
  }

  depends_on = [aws_iam_role_policy.lambda]
  tags       = { Name = "${var.project_name}-counter" }
}

resource "aws_iam_role" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2" {
  name = "${var.project_name}-app-policy"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.artifact.arn}/releases/*"
      },
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.counter.arn
      },
      {
        Effect = "Allow"
        Action = ["ssm:UpdateInstanceInformation", "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.project_name}-profile-"
  role        = aws_iam_role.ec2.name
}

resource "aws_lb" "app" {
  name               = "${local.common_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.common_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.app.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health/ready"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.instance.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region       = var.aws_region
    bucket_name      = aws_s3_bucket.artifact.id
    object_key       = aws_s3_object.app.key
    counter_function = aws_lambda_function.counter.function_name
    build_version    = substr(data.archive_file.app.output_md5, 0, 12)
    project_name     = var.project_name
  }))

  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-web" }
  }

  depends_on = [
    aws_iam_role_policy.ec2,
    aws_s3_object.app,
    aws_lambda_function.counter
  ]
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 240
  default_instance_warmup   = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
    precondition {
      condition     = var.min_size <= var.desired_capacity && var.desired_capacity <= var.max_size
      error_message = "Require min_size <= desired_capacity <= max_size."
    }
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-cpu-target"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/application"
  retention_in_days = 7
  tags              = { Name = "${var.project_name}-application-logs" }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  alarm_description   = "ALB target group has one or more unhealthy hosts."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  tags = { Name = "${var.project_name}-unhealthy-hosts" }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  alarm_description   = "Average EC2 CPU remains high for two periods."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  tags = { Name = "${var.project_name}-high-cpu" }
}
