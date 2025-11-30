data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  oltp_ami  = var.oltp_ami_id != "" ? var.oltp_ami_id : data.aws_ami.amazon_linux.id
  dwh_ami   = var.dwh_ami_id != "" ? var.dwh_ami_id : data.aws_ami.amazon_linux.id
  shiny_ami = var.shiny_ami_id != "" ? var.shiny_ami_id : data.aws_ami.amazon_linux.id
}

resource "aws_instance" "oltp" {
  ami                         = local.oltp_ami
  instance_type               = var.oltp_instance_type
  subnet_id                   = aws_subnet.oltp[local.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.oltp.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = false
  key_name                    = var.oltp_key_name != "" ? var.oltp_key_name : null

  root_block_device {
    volume_size = var.oltp_root_volume_gb
    encrypted   = true
  }

  tags = {
    Name = "clickstream-oltp"
    Role = "oltp"
  }
}

resource "aws_instance" "dwh" {
  ami                         = local.dwh_ami
  instance_type               = var.dwh_instance_type
  subnet_id                   = aws_subnet.analytics[local.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.analytics.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = false
  key_name                    = var.dwh_key_name != "" ? var.dwh_key_name : null

  root_block_device {
    volume_size = var.dwh_root_volume_gb
    encrypted   = true
  }

  tags = {
    Name = "clickstream-dwh"
    Role = "dwh"
  }
}

resource "aws_instance" "shiny" {
  ami                         = local.shiny_ami
  instance_type               = var.shiny_instance_type
  subnet_id                   = aws_subnet.analytics[length(local.azs) > 1 ? local.azs[1] : local.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.shiny.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = false
  key_name                    = var.shiny_key_name != "" ? var.shiny_key_name : null
  user_data                   = var.shiny_user_data

  root_block_device {
    volume_size = var.shiny_root_volume_gb
    encrypted   = true
  }

  tags = {
    Name = "clickstream-shiny"
    Role = "shiny"
  }
}

resource "aws_lb_target_group_attachment" "shiny" {
  count            = var.enable_shiny_alb ? 1 : 0
  target_group_arn = aws_lb_target_group.shiny[0].arn
  target_id        = aws_instance.shiny.id
  port             = var.shiny_port
}
