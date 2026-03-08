output "region" {
  value = var.region
}

output "environment" {
  value = var.environment
}

output "deploy_version" {
  value = var.deploy_version
}

output "instance_name" {
  description = "Environment + version, used for EC2 instance naming only"
  value       = local.instance_name
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.megaserver_api.repository_url
}

output "ecr_repository_name" {
  value = data.aws_ecr_repository.megaserver_api.name
}

output "cloudfront_domain" {
  description = "Public CloudFront URL for the API"
  value       = "https://${aws_cloudfront_distribution.api.domain_name}"
}

output "elastic_ip" {
  description = "Static IP of the ECS host (not directly accessible — CloudFront origin only)"
  value       = aws_eip.ecs_host.public_ip
}

output "api_desired_count" {
  description = "Desired task count for the ECS API service (var.api_desired_count)."
  value       = var.api_desired_count
}
