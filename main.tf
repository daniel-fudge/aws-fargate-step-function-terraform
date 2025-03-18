terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.29"
    }
  }
}

locals {
  project_name = "timer"
}

# VPC with IGW and two public Subnets
# ---------------------------------------------------------------------------------------
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
  tags = {Name = "${local.project_name}-VPC"}
}

resource "aws_subnet" "subnets" {
  count = length(var.subnet_cidrs)
  vpc_id = aws_vpc.main.id
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block = element(var.subnet_cidrs, count.index)
  tags = {Name = "${local.project_name}-${count.index}"}
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {Name = "${local.project_name}-IGW"}
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  tags = {Name = "${local.project_name}-RT"}
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
