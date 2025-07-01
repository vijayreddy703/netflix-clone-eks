
terraform {
  backend "s3" {
    bucket  = "gb-netflix-clone-007"
    key     = "netflix-clone/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}