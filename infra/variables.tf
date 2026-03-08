variable "aws_account_id" {
  description = "AWS account ID. Set via .env.local as AWS_ACCOUNT_ID."
  type        = string
}

variable "creds_file" {
  type    = string
  default = "~/.aws/credentials"
}

variable "creds_profile" {
  type    = string
  default = "default"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "deploy_version" {
  type        = string
  description = "Deployment version (e.g. git branch). Used with environment to create separate clusters."
  default     = "main"
}

variable "app_version" {
  type        = string
  description = "Docker image tag to deploy (e.g. git sha)."
}

variable "availability_zones" {
  description = "Availability zones to deploy into"
  type        = list(string)
  default     = []
}

variable "deploy_iam_user" {
  description = "IAM username to attach the deploy policy to"
  type        = string
}

variable "api_desired_count" {
  description = "Number of API instances to run. If set 0, all api instances will be stopped."
  type        = number
  default     = 1
}