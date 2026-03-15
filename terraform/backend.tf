terraform {
  backend "s3" {
    bucket         = "yosef-aviv-status-page-tf-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "yosef-aviv-status-page-tf-lock"
    encrypt        = true
  }
}
