provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-eks-state-s3-bucket-011110"

  lifecycle {
    prevent_destroy = false
  }
  tags = {
    Name = "tf state bucket "
  }
}