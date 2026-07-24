# New Relic Kubernetes integration: coleta métricas de CPU/memória dos pods
# e nodes, eventos do cluster e logs (via Fluent Bit embutido no chart),
# correlacionando com o APM da aplicação (instrumentado no repo da app).

resource "kubernetes_namespace" "newrelic" {
  metadata {
    name = "newrelic"
  }
}

resource "kubernetes_secret" "newrelic_license" {
  metadata {
    name      = "newrelic-license-key"
    namespace = kubernetes_namespace.newrelic.metadata[0].name
  }

  data = {
    licenseKey = var.new_relic_license_key
  }
}

resource "helm_release" "newrelic_bundle" {
  name       = "newrelic-bundle"
  repository = "https://helm-charts.newrelic.com"
  chart      = "nri-bundle"
  namespace  = kubernetes_namespace.newrelic.metadata[0].name
  version    = "5.0.94"

  set {
    name  = "global.licenseKey"
    value = var.new_relic_license_key
  }

  set {
    name  = "global.cluster"
    value = module.eks.cluster_name
  }

  set {
    name  = "newrelic-infrastructure.privileged"
    value = "true"
  }

  set {
    name  = "kubeEvents.enabled"
    value = "true"
  }

  set {
    name  = "logging.enabled"
    value = "true"
  }

  set {
    name  = "newrelic-prometheus-agent.lowDataMode"
    value = "true"
  }

  depends_on = [module.eks]
}
