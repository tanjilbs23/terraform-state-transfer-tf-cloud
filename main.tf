terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.30.0"
    }
  }
  cloud {
    organization = "personal-testing-terraform"

    workspaces {
      name = "terraform-state-transfer-tf-cloud"
    }
  }
}

provider "aws" {
  region  = "eu-west-1"
}



# S3 Bucket
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.4.0"

  bucket                  = var.bucket_name
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true

  website = {
    index_document = "index.html"
  }


  # Tags for the Bucket
  tags = {
    Name        = "terraform-state-testing-resource-september-2022"
    Environment = "DEV"
  }

}

# S3 Policy
data "aws_iam_policy_document" "this" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.s3_bucket.s3_bucket_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = module.cloudfront.cloudfront_origin_access_identity_iam_arns
    }
  }
}
# S3 bucket policy update for cloudfront
resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = module.s3_bucket.s3_bucket_id
  policy = data.aws_iam_policy_document.this.json
}
# s3 Policy End

# Cloudfront caching policy
data "aws_cloudfront_cache_policy" "this" {
  name = "Managed-CachingOptimized"
}

# Cloudfront
module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "2.9.3"

  comment             = "terraform-state-testing-resource-september-2022"
  enabled             = true
  is_ipv6_enabled     = false
  price_class         = "PriceClass_All"
  retain_on_delete    = false
  wait_for_deployment = false
  default_root_object = "index.html"

  create_origin_access_identity = true
  origin_access_identities = {
    s3_bucket_one = "terraform-state-testing-resource-september-2022-OAI"
  }
  origin = {

    s3_one = {
      domain_name = module.s3_bucket.s3_bucket_bucket_regional_domain_name

      s3_origin_config = {
        origin_access_identity = "s3_bucket_one"
      }
      origin_shield = {
        enabled              = true
        origin_shield_region = "eu-west-1"
      }
    }
  }

  custom_error_response = [
    {
      "error_caching_min_ttl" = 300,
      "error_code"            = 400,
      "response_code"         = 200,
      "response_page_path"    = "/index.html",
    },
    {
      "error_caching_min_ttl" = 300,
      "error_code"            = 403,
      "response_code"         = 200,
      "response_page_path"    = "/index.html",
    },
    {
      "error_caching_min_ttl" = 300,
      "error_code"            = 404,
      "response_code"         = 200,
      "response_page_path"    = "/index.html",
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3_one"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods      = ["GET", "HEAD", "OPTIONS"]
    cached_methods       = ["GET", "HEAD", "OPTIONS"]
    compress             = true
    query_string         = true
    cache_policy_id      = data.aws_cloudfront_cache_policy.this.id
    use_forwarded_values = false
  }


  geo_restriction = {
    restriction_type = "none"
  }

  tags = {
    Environment = "DEV"
  }

  viewer_certificate = {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = "sni-only"
  }
}
