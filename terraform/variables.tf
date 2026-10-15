variable "aws_region" {
  description = "AWS region for this educational stack."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short prefix for project resource names."
  type        = string
  default     = "aws-capstone"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "instance_type" {
  description = "EC2 instance type. Confirm availability and pricing in the chosen region."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  type        = number
  description = "Minimum Auto Scaling capacity."
  default     = 2
}

variable "desired_capacity" {
  type        = number
  description = "Desired Auto Scaling capacity."
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Maximum Auto Scaling capacity."
  default     = 4
}

variable "cpu_target" {
  type        = number
  description = "Target average CPU utilization for target tracking."
  default     = 60
}
