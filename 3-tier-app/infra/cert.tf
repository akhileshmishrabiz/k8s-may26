# pull the public hosted zone id from route 53
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Create the certificate

resource "aws_acm_certificate" "app" {
  domain_name       = "${var.app_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.prefix}-cert"
  }
}

# Create Route53 record for ACM certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
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

# Validate the ACM certificate
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Create Route53 alias record to point subdomain to ALB
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = kubernetes_ingress_v1.app_ingress_tls.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = "ZP97RAFLXTNZK"
    evaluate_target_health = true
  }

  depends_on = [kubernetes_ingress_v1.app_ingress_tls]
}