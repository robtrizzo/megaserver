provider "aws" {
  shared_credentials_files = [var.creds_file]
  profile                  = var.creds_profile
  region                   = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/DeployRole"
  }
}

data "aws_ami" "ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-x86_64"]
  }

  owners = ["amazon"]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availabilityZone"
    values = var.availability_zones
  }
}

locals {
  subnet_id       = data.aws_subnets.default.ids[0]
  version_safe    = replace(var.deploy_version, "/", "-")
  # Only used for EC2 instance (and EIP) naming so multiple instances per environment can exist (e.g. dev-main, dev-feature).
  instance_name = "${var.environment}-${local.version_safe}"
}

# CloudFront managed prefix list — restricts EC2 ingress to CloudFront IPs only
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "docker_host" {
  name_prefix = "docker-host-${var.environment}-"
  vpc_id      = data.aws_vpc.default.id

  # Only allow HTTP from CloudFront (no direct public access)
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
    description     = "HTTP from CloudFront only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docker-host-${var.environment}"
  }
}

data "aws_ecr_repository" "megaserver_api" {
  name = "megaserver/megaserver-api"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/megaserver-${var.environment}"
  retention_in_days = 14
  tags = {
    Environment = var.environment
    Application = "megaserver-api"
  }
}

resource "aws_ecs_cluster" "main" {
  name = "megaserver-${var.environment}"
}

resource "aws_iam_role" "ecs_task_execution" {
  name_prefix = "ecs-task-execution-${var.environment}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Service   = "ecs-task-execution"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_instance" {
  name_prefix = "ecs-instance-${var.environment}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_service" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecr" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name_prefix = "ecs-instance-${var.environment}-"
  role        = aws_iam_role.ecs_instance.name
}

resource "aws_iam_role" "ecs_task" {
  name_prefix = "ecs-task-${var.environment}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Service   = "ecs-task"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_policy" "ecs_task_policy" {
  name_prefix = "ecs-app-task-policy-${var.environment}-"
  description = "Permissions for the ECS application containers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::app-data-bucket",
          "arn:aws:s3:::app-data-bucket/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

resource "aws_instance" "ecs_host" {
  ami                    = data.aws_ami.ecs.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance.name
  vpc_security_group_ids = [aws_security_group.docker_host.id]
  # No public IP assigned at launch — EIP handles the static public address
  associate_public_ip_address = false

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
  EOF
  )

  tags = {
    Name = "ecs-megaserver-${local.instance_name}"
  }
}

resource "aws_eip" "ecs_host" {
  domain = "vpc"
  tags = {
    Name = "ecs-host-${local.instance_name}"
  }
}

resource "aws_eip_association" "ecs_host" {
  instance_id   = aws_instance.ecs_host.id
  allocation_id = aws_eip.ecs_host.id
}

resource "aws_ecs_task_definition" "api" {
  family                   = "megaserver-api-${var.environment}"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${data.aws_ecr_repository.megaserver_api.repository_url}:${var.app_version}"
      essential = true
      portMappings = [
        {
          containerPort = 4000
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:4000/v1/healthcheck || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = "megaserver-api-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "EC2"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  depends_on = [aws_instance.ecs_host]
}

resource "aws_cloudfront_distribution" "api" {
  enabled          = true
  is_ipv6_enabled  = true
  comment          = "megaserver-${var.environment}"
  price_class      = "PriceClass_100"
  retain_on_delete = true

  origin {
    domain_name = aws_eip.ecs_host.public_dns
    origin_id   = "ec2-ecs-host"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "ec2-ecs-host"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations = [
        # North America
        "US", "CA", "MX",
        # Europe
        "GB", "DE", "FR", "IT", "ES", "NL", "BE", "CH", "AT", "SE",
        "NO", "DK", "FI", "PT", "IE", "LU", "IS", "LI",
      ]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Application = "megaserver-api"
  }
}
