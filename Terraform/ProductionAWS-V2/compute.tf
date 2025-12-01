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
  oltp_ami      = var.oltp_ami_id != "" ? var.oltp_ami_id : data.aws_ami.amazon_linux.id
  analytics_ami = var.analytics_ami_id != "" ? var.analytics_ami_id : data.aws_ami.amazon_linux.id
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

resource "aws_instance" "analytics" {
  ami                         = local.analytics_ami
  instance_type               = var.analytics_instance_type
  subnet_id                   = aws_subnet.analytics[length(local.azs) > 1 ? local.azs[1] : local.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.analytics.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = false
  key_name                    = var.analytics_key_name != "" ? var.analytics_key_name : null
  user_data                   = var.shiny_user_data

  root_block_device {
    volume_size = var.analytics_root_volume_gb
    encrypted   = true
  }

  tags = {
    Name = "clickstream-analytics"
    Role = "dwh+shiny"
  }
}

resource "aws_lb_target_group_attachment" "shiny" {
  target_group_arn = aws_lb_target_group.shiny.arn
  target_id        = aws_instance.analytics.id
  port             = var.shiny_port
}

resource "aws_lb_target_group_attachment" "privatelink" {
  target_group_arn = aws_lb_target_group.privatelink.arn
  target_id        = aws_instance.analytics.id
  port             = var.shiny_port
}
