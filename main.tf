# main.tf

provider "aws" {
  region = "us-east-1"  # specify your AWS region
}

# Replace these values with your existing VPC and subnet IDs
variable "vpc_id" {
  description = "The ID of the VPC where MWAA will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "The IDs of the subnets where MWAA will be deployed"
  type        = list(string)
}

variable "mwaa_bucket_name" {
  description = "The name of the S3 bucket for MWAA"
  type        = string
  default     = "airflow-bucket-omkar"  # Replace with your bucket name if different
}

resource "aws_s3_bucket" "mwaa_bucket" {
  bucket = var.mwaa_bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "log"
    enabled = true

    expiration {
      days = 90
    }
  }
}


resource "aws_s3_bucket_public_access_block" "mwaa_bucket_public_access_block" {
  bucket = aws_s3_bucket.mwaa_bucket.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



resource "aws_s3_bucket_object" "dags_folder" {
  bucket = aws_s3_bucket.mwaa_bucket.bucket
  key    = "dags/"
  acl    = "private"
}


resource "aws_iam_role" "mwaa_execution_role" {
  name = "mwaa_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "airflow-env.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "mwaa_execution_policy" {
  role = aws_iam_role.mwaa_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListAllMyBuckets",
          "s3:GetBucketPublicAccessBlock"
        ],
        Resource = [
          "${aws_s3_bucket.mwaa_bucket.arn}",
          "${aws_s3_bucket.mwaa_bucket.arn}/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_mwaa_environment" "example" {
  name                = "example-mwaa-environment"
  airflow_version     = "2.8.1"  # Update to a supported Airflow version
  environment_class   = "mw1.small"
  execution_role_arn  = aws_iam_role.mwaa_execution_role.arn
  source_bucket_arn   = aws_s3_bucket.mwaa_bucket.arn
  dag_s3_path         = "dags"
  network_configuration {
    security_group_ids = [aws_security_group.mwaa_sg.id]
    subnet_ids         = var.subnet_ids
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }

    task_logs {
      enabled   = true
      log_level = "INFO"
    }

    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }

    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  weekly_maintenance_window_start = "SUN:03:00"
}

resource "aws_security_group" "mwaa_sg" {
  name        = "mwaa_security_group"
  description = "Security group for MWAA"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
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

output "airflow_ui_url" {
  value       = aws_mwaa_environment.example.webserver_url
  description = "URL of the Airflow UI"
}






