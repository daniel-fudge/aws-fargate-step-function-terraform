terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.29"
    }
  }
}

variable "project_name" {
  type = string
  description = "Project name prefix for resources"
  default = "timer"
}

# VPC with IGW and two public Subnets
# ----------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

variable "subnet_cidrs" {
  type = list(string)
  description = "Subnet CIDR values"
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "vpc_cidr" {
  type = string
  description = "VPC CIDR value"
  default = "10.0.0.0/16"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {Name = "${var.project_name}-VPC"}
}

resource "aws_subnet" "subnets" {
  count = length(var.subnet_cidrs)
  vpc_id = aws_vpc.main.id
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block = element(var.subnet_cidrs, count.index)
  tags = {Name = "${var.project_name}-${count.index}"}
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {Name = "${var.project_name}-IGW"}
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  tags = {Name = "${var.project_name}-RT"}
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "subnets" {
  count = length(var.subnet_cidrs)
  route_table_id = aws_route_table.main.id
  subnet_id = element(aws_subnet.subnets[*].id, count.index)
}

# Fargate-ECS Task
# ---------------------------------------------------------------------------------------- 
variable "bucket" {
  type = string
  description = "Bucket to store task output"
}

resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
  tags = {Name = "${var.project_name}-SG"}
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-Cluster"
}

resource "aws_iam_role" "task_role" {
  name = "${var.project_name}-Task-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {Service = "ecs-tasks.amazonaws.com"}
    }]
  })
}

resource "aws_iam_role_policy" "task_policy" {
  name = "${var.project_name}-Task-Role-Policy"
  role = aws_iam_role.task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "s3:PutObject"
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${var.bucket}/*"
      },
    ]
  })
}

resource "aws_iam_role" "exec_role" {
  name = "${var.project_name}-Exec-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {Service = "ecs-tasks.amazonaws.com"}
    }]
  })
}

resource "aws_iam_role_policy" "exec_policy" {
  name = "${var.project_name}-Exec-Role-Policy"
  role = aws_iam_role.exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:::log-group:/ecs/${var.project_name}:*"
      },
      {
        Effect   = "Allow"
        Action = "ecr:GetAuthorizationToken"
        Resource = aws_ecs_cluster.main.arn
      }
    ]
  })
}
