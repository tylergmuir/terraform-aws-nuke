provider "aws" {
    region = var.aws_region
    profile = var.aws_profile
    default_tags {
        tags = {
            expirationdate = formatdate("YYYY-MM-DD", timeadd(timestamp(), "-180h"))
        }
    }
}
