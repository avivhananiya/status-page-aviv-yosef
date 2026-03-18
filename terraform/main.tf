# -------------------------
# Shared Data Sources & Locals
# -------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "yosef-aviv-status-page-${var.env}"
  domain_name = "yosef-aviv-statuspage.xyz"
}
