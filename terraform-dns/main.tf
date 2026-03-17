locals {
  domain_name = "yosef-aviv-statuspage.xyz"
}

resource "aws_route53_zone" "main" {
  name = local.domain_name
}