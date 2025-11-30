locals {
  public_subnet_cidrs    = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i)]
  oltp_subnet_cidrs      = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i + 2)]
  analytics_subnet_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i + 4)]
}

resource "aws_vpc" "clickstream" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.clickstream.id
}

resource "aws_subnet" "public" {
  for_each = zipmap(local.azs, local.public_subnet_cidrs)

  vpc_id                  = aws_vpc.clickstream.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Tier = "public"
  }
}

resource "aws_subnet" "oltp" {
  for_each = zipmap(local.azs, local.oltp_subnet_cidrs)

  vpc_id                  = aws_vpc.clickstream.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = {
    Tier = "oltp"
  }
}

resource "aws_subnet" "analytics" {
  for_each = zipmap(local.azs, local.analytics_subnet_cidrs)

  vpc_id                  = aws_vpc.clickstream.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = {
    Tier = "analytics"
  }
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  vpc   = true
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[local.azs[0]].id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.clickstream.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "oltp" {
  vpc_id = aws_vpc.clickstream.id
}

resource "aws_route_table" "analytics" {
  vpc_id = aws_vpc.clickstream.id
}

resource "aws_route" "oltp_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.oltp.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route" "analytics_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.analytics.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "oltp_assoc" {
  for_each = aws_subnet.oltp

  subnet_id      = each.value.id
  route_table_id = aws_route_table.oltp.id
}

resource "aws_route_table_association" "analytics_assoc" {
  for_each = aws_subnet.analytics

  subnet_id      = each.value.id
  route_table_id = aws_route_table.analytics.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.clickstream.id
  vpc_endpoint_type = "Gateway"
  service_name    = "com.amazonaws.${data.aws_region.current.name}.s3"

  route_table_ids = [
    aws_route_table.oltp.id,
    aws_route_table.analytics.id
  ]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:*",
      Resource  = "*",
      Condition = {
        StringEquals = {
          "aws:SourceVpc" = aws_vpc.clickstream.id
        }
      }
    }]
  })
}

resource "aws_security_group" "lambda" {
  name        = "lambda-sg"
  description = "Egress for Lambda functions"
  vpc_id      = aws_vpc.clickstream.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "oltp" {
  name        = "oltp-sg"
  description = "OLTP database access"
  vpc_id      = aws_vpc.clickstream.id

  ingress {
    description      = "Lambda to OLTP"
    from_port        = var.oltp_port
    to_port          = var.oltp_port
    protocol         = "tcp"
    security_groups  = [aws_security_group.lambda.id]
  }

  ingress {
    description     = "Analytics to OLTP"
    from_port       = var.oltp_port
    to_port         = var.oltp_port
    protocol        = "tcp"
    security_groups = [aws_security_group.analytics.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "analytics" {
  name        = "analytics-sg"
  description = "Warehouse access"
  vpc_id      = aws_vpc.clickstream.id

  ingress {
    description     = "Lambda to DWH"
    from_port       = var.dwh_port
    to_port         = var.dwh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  ingress {
    description     = "Shiny to DWH"
    from_port       = var.dwh_port
    to_port         = var.dwh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.shiny.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "shiny" {
  name        = "shiny-sg"
  description = "Shiny access"
  vpc_id      = aws_vpc.clickstream.id

  ingress {
    description     = "ALB to Shiny"
    from_port       = var.shiny_port
    to_port         = var.shiny_port
    protocol        = "tcp"
    security_groups = var.enable_shiny_alb ? [aws_security_group.shiny_alb[0].id] : []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "shiny_alb" {
  count       = var.enable_shiny_alb ? 1 : 0
  name        = "shiny-alb-sg"
  description = "Ingress for Shiny ALB"
  vpc_id      = aws_vpc.clickstream.id

  dynamic "ingress" {
    for_each = var.allowed_admin_cidrs
    content {
      description      = "Admin access"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "shiny" {
  count              = var.enable_shiny_alb ? 1 : 0
  name               = "shiny-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.shiny_alb[0].id]
  subnets            = [for az in local.azs : aws_subnet.analytics[az].id]
}

resource "aws_lb_target_group" "shiny" {
  count    = var.enable_shiny_alb ? 1 : 0
  name     = "shiny-tg"
  port     = var.shiny_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.clickstream.id
  health_check {
    path                = "/"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "shiny_http" {
  count             = var.enable_shiny_alb ? 1 : 0
  load_balancer_arn = aws_lb.shiny[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shiny[0].arn
  }
}
