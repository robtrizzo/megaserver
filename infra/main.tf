provider "aws" {
  shared_credentials_files = [var.creds_file]
  profile                  = var.creds_profile
  region                   = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "allow_ssh" {
  name_prefix = "allow_ssh"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  key_name      = aws_key_pair.generated_key.key_name

  tags = {
    Name = "base-terraform"
  }
}

resource "aws_key_pair" "generated_key" {
  key_name   = "tf-generated-key"
  public_key = tls_private_key.autokey.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content  = tls_private_key.autokey.private_key_pem
  filename = ".terraform/tf-generated-key.pem"
  # Set proper file permissions for the private key
  file_permission = "0400"
}
