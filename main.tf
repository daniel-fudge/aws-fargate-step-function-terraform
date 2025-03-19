terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.91"
    }
  }
}

data "aws_caller_identity" "current" {}

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

variable "region" {
  type = string
  description = "The region to deploy the stack into"
  default = "us-east-1"
}

resource "aws_security_group" "main" {
  vpc_id = aws_vpc.main.id
  tags = {Name = "${var.project_name}-SG"}
}

resource "aws_vpc_security_group_egress_rule" "main" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
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
        Resource = "arn:aws:logs:${data.aws_caller_identity.current.account_id}:${var.region}:log-group:/ecs/${var.project_name}:*"
      },
      {
        Effect   = "Allow"
        Action = "ecr:GetAuthorizationToken"
        Resource = aws_ecs_cluster.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "AWS_task_exec_policy_attach" {
  role       = "${aws_iam_role.exec_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "main" {
  family = "${var.project_name}-Task-Definition"
  task_role_arn = aws_iam_role.task_role.arn
  execution_role_arn = aws_iam_role.exec_role.arn
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = 256
  memory = 512
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "X86_64"
  }
  container_definitions = <<TASK_DEFINITION
[
  {
    "name": "${var.project_name}",
    "image": "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.project_name}:latest",
    "cpu": 0,
    "portMappings": [{"containerPort": 80, "hostPort": 80, "Protocol": "tcp"}],
    "essential": true,
    "entryPoint": ["python3.13"],
    "LogConfiguration": { 
      "LogDriver": "awslogs",
      "Options": { 
        "awslogs-region": "${var.region}",
        "awslogs-group": "/ecs/${var.project_name}",
        "mode": "non-blocking",
        "awslogs-create-group": "true",
        "max-buffer-size": "25m",
        "awslogs-stream-prefix": "ecs"    
      }
    }
  }
]
TASK_DEFINITION
}

# Step Function
# ---------------------------------------------------------------------------------------- 
resource "aws_iam_role" "step_role" {
  name = "${var.project_name}-Step-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {Service = "states.${var.region}.amazonaws.com"}
    }]
  })
}

data "aws_iam_policy_document" "step_policy_doc" {
  statement {
    actions = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test = "StringLike"
      variable = "iam:PassedToService"
      values = ["ecs-tasks.amazonaws.com"]
    }
  }
  statement {
    actions = ["ecs:RunTask"]
    resources = ["${aws_ecs_task_definition.main.arn_without_revision}:*"]
  }
  statement {
    actions = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task/${var.project_name}/*"]
  }
  statement {
    actions = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:aws:events:${var.region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
  }
}

resource "aws_iam_role_policy" "step_policy" {
  name = "${var.project_name}-Step-Role-Policy"
  role = aws_iam_role.step_role.id
  policy = data.aws_iam_policy_document.step_policy_doc.json
}

resource "aws_sfn_state_machine" "main" {
  name = "${var.project_name}-Step-Function"
  role_arn = aws_iam_role.step_role.arn

  definition = <<EOF
{
  "QueryLanguage": "JSONPath",
  "Comment": "A delayed batch of Fargate timers",
  "StartAt": "Timer-Batch",
  "States": {
    "Timer-Batch": {
      "Type": "Map",
      "End": true,
      "ItemsPath": "$.timer_info",
      "ItemProcessor": {
        "ProcessorConfig": {"Mode": "INLINE"},
        "StartAt": "Wait",
        "States": {
          "Wait": {
            "Type": "Wait",
            "SecondsPath": "$.delay",
            "Next": "Timer-Fargate"},
          "Timer-Fargate": {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.sync",
            "End": true,
            "Parameters": {
              "LaunchType": "FARGATE",
              "Cluster": "${aws_ecs_cluster.main.arn}",
              "TaskDefinition": "${aws_ecs_task_definition.main.arn_without_revision}",
              "NetworkConfiguration": {
                "AwsvpcConfiguration": {
                  "Subnets": ["${aws_subnet.subnets[0].id}", "${aws_subnet.subnets[1].id}"],
                  "SecurityGroups": ["${aws_security_group.main.id}"],
                  "AssignPublicIp": "ENABLED"}},
              "Overrides": {
                "ContainerOverrides": [{
                  "Name": "${var.project_name}",
                  "Command.$": "$.commands"}]
              }
            }
          }
        }
      }
    }
  }
}
EOF
}

# Ouput
# ---------------------------------------------------------------------------------------- 
output "step_cmd" {
  value = join("", [
    "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.main.arn} --input '{\"timer_info\": [",
    "{\"delay\": 0, \"commands\": [\"app.py\", \"--job_id\", \"1\", \"--duration\", \"3\", \"--bucket\", \"${var.bucket}\"]}, ",
    "{\"delay\": 2, \"commands\": [\"app.py\", \"--job_id\", \"2\", \"--duration\", \"4\", \"--bucket\", \"${var.bucket}\"]}]}\"'"])
}
output "task_cmd" {
  value = join("", [
    "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.main.arn} --input '{\"timer_info\": [",
    "{\"delay\": 0, \"commands\": [\"app.py\", \"--job_id\", \"1\", \"--duration\", \"3\", \"--bucket\", \"${var.bucket}\"]}, ",
    "{\"delay\": 2, \"commands\": [\"app.py\", \"--job_id\", \"2\", \"--duration\", \"4\", \"--bucket\", \"${var.bucket}\"]}]}\"'"])
}
