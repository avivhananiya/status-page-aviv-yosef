# ==========================================
# Route 53 Zone Data
# ==========================================
data "aws_route53_zone" "main" {
  name         = local.domain_name
  private_zone = false
}

# ==========================================
# ACM Certificate & DNS Validation
# ==========================================
resource "aws_acm_certificate" "cert" {
  domain_name               = local.domain_name
  subject_alternative_names = ["*.${local.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${local.name_prefix}-cert"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ==========================================
# DNS Failover — S3 Static Page + Route 53 + Alerting
# ==========================================
# NOTE: The ALB is created by the AWS Load Balancer Controller when the
#       K8s Ingress is applied — it does not exist before the first deploy.
#       Deploy order: terraform apply → kubectl apply → terraform apply -var="enable_dns_failover=true"

data "aws_lb" "alb" {
  count = var.enable_dns_failover ? 1 : 0
  name  = "status-page-alb"
}

# S3 bucket for failover page (bucket name must match domain for Route 53 Alias)
resource "aws_s3_bucket" "failover_page" {
  bucket = local.domain_name
  tags = {
    Name        = "${local.name_prefix}-failover-page"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "failover_page" {
  bucket = aws_s3_bucket.failover_page.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "failover_page" {
  bucket = aws_s3_bucket.failover_page.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "failover_page" {
  bucket = aws_s3_bucket.failover_page.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.failover_page.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.failover_page]
}

resource "aws_s3_object" "failover_index" {
  bucket       = aws_s3_bucket.failover_page.id
  key          = "index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Status Page</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
          margin: 0;
          background: #f5f5f5;
          color: #333;
        }
        .container {
          text-align: center;
          max-width: 500px;
          padding: 2rem;
        }
        h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
        p { color: #666; line-height: 1.6; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>We are investigating</h1>
        <p>Our status page is temporarily unavailable. The team has been
        notified and is working to restore service. Please check back shortly.</p>
      </div>
    </body>
    </html>
  HTML
}

# ==========================================
# Route 53 Failover Records
# ==========================================
resource "aws_route53_record" "primary" {
  count   = var.enable_dns_failover ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = data.aws_lb.alb[0].dns_name
    zone_id                = data.aws_lb.alb[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count   = var.enable_dns_failover ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = aws_s3_bucket_website_configuration.failover_page.website_domain
    zone_id                = aws_s3_bucket.failover_page.hosted_zone_id
    evaluate_target_health = false
  }
}

# ==========================================
# Health Check & Alerting
# ==========================================
resource "aws_route53_health_check" "alb" {
  count             = var.enable_dns_failover ? 1 : 0
  fqdn              = data.aws_lb.alb[0].dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "${local.name_prefix}-alb-health"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_sns_topic" "failover_alert" {
  count = var.enable_dns_failover ? 1 : 0
  name  = "${local.name_prefix}-failover-alert"
  tags = {
    Name        = "${local.name_prefix}-failover-alert"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "failover" {
  count               = var.enable_dns_failover ? 1 : 0
  alarm_name          = "${local.name_prefix}-failover-alert"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Status Page ALB health check failed — DNS failover activated"
  alarm_actions       = [aws_sns_topic.failover_alert[0].arn]
  ok_actions          = [aws_sns_topic.failover_alert[0].arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.alb[0].id
  }

  tags = {
    Name        = "${local.name_prefix}-failover-alarm"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}
