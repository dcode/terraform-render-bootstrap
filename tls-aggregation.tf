locals {
  _agg_ca_cert_generated = one(tls_self_signed_cert.aggregation-ca[*].cert_pem)
  _agg_ca_key_generated  = one(tls_private_key.aggregation-ca[*].private_key_pem)
  # try catches the all-null case when aggregation is disabled and no cert is injected
  effective_aggregation_ca_cert = replace(try(coalesce(var.aggregation_ca_cert, local._agg_ca_cert_generated), ""), "\\n", "\n")
  effective_aggregation_ca_key  = replace(try(coalesce(var.aggregation_ca_key, local._agg_ca_key_generated), ""), "\\n", "\n")
}

locals {
  # Kubernetes Aggregation TLS assets map
  aggregation_tls = var.enable_aggregation ? {
    "tls/k8s/aggregation-ca.crt"     = local.effective_aggregation_ca_cert,
    "tls/k8s/aggregation-client.crt" = tls_locally_signed_cert.aggregation-client[0].cert_pem,
    "tls/k8s/aggregation-client.key" = tls_private_key.aggregation-client[0].private_key_pem,
  } : {}
}

# Kubernetes Aggregation CA (i.e. front-proxy-ca)
# Files: tls/{aggregation-ca.crt,aggregation-ca.key}

resource "tls_private_key" "aggregation-ca" {
  count = var.enable_aggregation && var.aggregation_ca_cert == null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_self_signed_cert" "aggregation-ca" {
  count = var.enable_aggregation && var.aggregation_ca_cert == null ? 1 : 0

  private_key_pem = tls_private_key.aggregation-ca[0].private_key_pem

  subject {
    common_name = "kubernetes-front-proxy-ca"
  }

  is_ca_certificate     = true
  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
  ]
}

# Kubernetes apiserver (i.e. front-proxy-client)
# Files: tls/{aggregation-client.crt,aggregation-client.key}

resource "tls_private_key" "aggregation-client" {
  count = var.enable_aggregation ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "aggregation-client" {
  count = var.enable_aggregation ? 1 : 0

  private_key_pem = tls_private_key.aggregation-client[0].private_key_pem

  subject {
    common_name = "kube-apiserver"
  }
}

resource "tls_locally_signed_cert" "aggregation-client" {
  count = var.enable_aggregation ? 1 : 0

  cert_request_pem = tls_cert_request.aggregation-client[0].cert_request_pem

  ca_private_key_pem = local.effective_aggregation_ca_key
  ca_cert_pem        = local.effective_aggregation_ca_cert

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

