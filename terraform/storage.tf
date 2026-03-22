# -------------------------
# S3 Bucket for Static Files
# -------------------------
resource "random_string" "s3_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "static_files" {
  bucket = "status-page-yosef-aviv-${random_string.s3_suffix.result}"

  tags = {
    Name        = "${local.name_prefix}-static-files"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_cors_configuration" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["https://yosef-aviv-statuspage.xyz"]
    max_age_seconds = 86400
  }
}

resource "aws_s3_bucket_public_access_block" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static_files" {
  bucket = aws_s3_bucket.static_files.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_files.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_files]
}

# -------------------------
# ECR Repository for Application Images
# -------------------------
resource "aws_ecr_repository" "app" {
  name                 = local.name_prefix
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = true
}
