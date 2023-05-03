terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.64.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }

  backend "remote" {
    organization = "lavalabs"

    workspaces {
      name = "gpt4slack"
    }
  }
}

provider "aws" {
  profile = "lavalabs-infra"
  default_tags {
    tags = {
      terraformed = true
      github_repo = "https://github.com/lavagames/gpt4slack"
    }
  }
}

resource "aws_ecr_repository" "this" {
  name         = "gpt4slack"
  force_delete = true
}

locals {
  tag   = substr(trimspace(file(".git/${trimspace(trimprefix(file(".git/HEAD"), "ref:"))}")), 0, 7)
  image = "${aws_ecr_repository.this.repository_url}:${local.tag}"
}

resource "docker_image" "this" {
  name = "gpt4slack"
  build {
    tag             = [local.image]
    context         = "."
    suppress_output = false
    platform        = "linux/arm64"
  }

  lifecycle { create_before_destroy = true }
  triggers = {
    dockerfile = filesha1("Dockerfile")
    script     = filesha1("gpt4slack.py")
  }

  depends_on = [aws_ecr_repository.this]
  provisioner "local-exec" { command = "docker push ${local.image}" }
}

data "aws_ecs_cluster" "services" { cluster_name = "services" }

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["infra"]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
  filter {
    name   = "tag:state"
    values = ["private"]
  }
}

module "container_definition" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "0.58.2"

  container_name    = "gpt4slack"
  container_image   = local.image
  log_configuration = {
    logDriver : "awslogs",
    options : {
      awslogs-group : "/ecs/gpt4slack",
      awslogs-region : "eu-west-1",
      awslogs-create-group : "true",
      awslogs-stream-prefix : "ecs"
    }
  }
  map_secrets = {
    OPENAI_API_KEY  = "arn:aws:ssm:eu-west-1:094672092421:parameter/gpt4slack/OPENAI_API_KEY"
    SLACK_BOT_TOKEN = "arn:aws:ssm:eu-west-1:094672092421:parameter/gpt4slack/SLACK_BOT_TOKEN"
    SLACK_APP_TOKEN = "arn:aws:ssm:eu-west-1:094672092421:parameter/gpt4slack/SLACK_APP_TOKEN"
  }

  depends_on = [docker_image.this]
}

resource "aws_ecs_task_definition" "taskdef" {
  container_definitions    = module.container_definition.json_map_encoded_list
  family                   = "gpt4slack"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  skip_destroy       = true
  execution_role_arn = aws_iam_role.gpt4slack-exec.arn
}

resource "aws_ecs_service" "gpt4slack" {
  name                 = "gpt4slack"
  cluster              = data.aws_ecs_cluster.services.arn
  desired_count        = 1
  force_new_deployment = true
  launch_type          = "FARGATE"
  task_definition      = aws_ecs_task_definition.taskdef.arn

  network_configuration {
    subnets = data.aws_subnets.subnets.ids
  }

  triggers = {
    task_definition = aws_ecs_task_definition.taskdef.arn
  }
}

resource "aws_iam_role_policy" "gpt4slack-exec" {
  name = "gpt4slack-exec"
  role = aws_iam_role.gpt4slack-exec.id

  policy = jsonencode(
    {
      Version   = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "logs:PutLogEvents",
            "logs:CreateLogStream",
            "logs:CreateLogGroup",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetAuthorizationToken",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability"
          ],
          Resource = "*"
        },
        {
          Effect = "Allow",
          Action = [
            "ssm:GetParameters",
          ],
          Resource = "arn:aws:ssm:eu-west-1:094672092421:parameter/gpt4slack/*"
        }
      ]
    })
}

resource "aws_iam_role" "gpt4slack-exec" {
  name = "gpt4slack-exec"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Sid       = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}