terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}

resource "tls_private_key" "autokey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}