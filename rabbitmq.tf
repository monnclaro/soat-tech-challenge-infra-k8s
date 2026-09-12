# RabbitMQ (Fase 4): broker de mensageria compartilhado entre os 3 microsserviços
# (soat-os-service / soat-billing-service / soat-execucao-service) para a saga
# orquestrada da Ordem de Serviço — infraestrutura de plataforma provisionada uma
# única vez aqui, mesmo racional do New Relic acima (um chart por cluster, não um
# por serviço). 1 réplica só, sem alta disponibilidade: projeto acadêmico, e o
# node group t3.small não tem folga para um cluster RabbitMQ maior.

resource "kubernetes_namespace" "rabbitmq" {
  metadata {
    name = "rabbitmq"
  }
}

resource "random_password" "rabbitmq" {
  length  = 32
  special = false # apenas alfanumérico: evita escaping ao injetar como env var
}

resource "helm_release" "rabbitmq" {
  name       = "rabbitmq"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq"
  namespace  = kubernetes_namespace.rabbitmq.metadata[0].name
  version    = "15.2.5"

  set {
    name  = "auth.username"
    value = "soat"
  }

  set_sensitive {
    name  = "auth.password"
    value = random_password.rabbitmq.result
  }

  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "persistence.size"
    value = "1Gi"
  }

  # Requests/limits enxutos de propósito: 3 APIs + este broker + MongoDB
  # (repo do Execução Service) + o agente do New Relic disputam o mesmo
  # node group t3.small (ver bump de node_min_size em variables.tf).
  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "150m"
  }

  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "350m"
  }

  depends_on = [aws_eks_node_group.default]
}

# Publicados em SSM para os 3 repositórios de microsserviço consumirem no
# deploy (CI/CD gera o Secret do deployment com RabbitMq__Host/Username/Password
# a partir daqui) — mesmo padrão do segredo JWT em jwt.tf.
resource "aws_ssm_parameter" "rabbitmq_host" {
  name  = "/soat/${var.environment}/rabbitmq/host"
  type  = "String"
  value = "rabbitmq.${kubernetes_namespace.rabbitmq.metadata[0].name}.svc.cluster.local"
}

resource "aws_ssm_parameter" "rabbitmq_username" {
  name  = "/soat/${var.environment}/rabbitmq/username"
  type  = "String"
  value = "soat"
}

resource "aws_ssm_parameter" "rabbitmq_password" {
  name  = "/soat/${var.environment}/rabbitmq/password"
  type  = "SecureString"
  value = random_password.rabbitmq.result
}
