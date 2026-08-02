# Cluster EKS com node group gerenciado e escalabilidade (o HPA, provisionado
# pelo repo da aplicação, escala os pods dentro do node group).
#
# IAM restrito (AWS Academy): não criamos nenhuma role — cluster e node group
# reaproveitam a LabRole já existente na conta (var.lab_role_arn). Por isso
# também: sem OIDC provider (IRSA) e sem KMS key própria para envelope
# encryption dos Secrets do cluster (kms:CreateKey também costuma estar fora
# da policy do Academy). Ver ADR 0008.
#
# Recursos escritos à mão (aws_eks_cluster/aws_eks_node_group/aws_eks_addon),
# não o módulo terraform-aws-modules/eks/aws: o módulo declara internamente
# um data "aws_iam_session_context" incondicional, que chama iam:GetRole na
# role por trás da sessão STS do Academy ("voclabs") — e o Academy tem um deny
# explícito pra essa chamada (policy Pvoclabs2), em toda versão do módulo
# testada (19.x/20.x/21.x), mesmo quando o valor resolvido não é usado pela
# nossa configuração. Escrevendo os recursos direto, essa chamada nunca
# acontece.

resource "aws_eks_cluster" "this" {
  name     = "soat-${var.environment}"
  version  = var.cluster_version
  role_arn = var.lab_role_arn

  vpc_config {
    subnet_ids             = module.vpc.public_subnets
    endpoint_public_access = true
  }

  tags = {
    Ambiente = var.environment
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = module.vpc.public_subnets

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  labels = {
    workload = "soat-api"
  }

  tags = {
    Ambiente = var.environment
  }
}

# EKS cria e anexa automaticamente a "cluster security group" aos nodes, mas
# ela não libera nada pra internet por padrão — precisa dessa regra explícita
# pro API Gateway (repo lambda) alcançar o Service NodePort direto no node,
# já que não tem ALB na frente (ver ADR 0008).
resource "aws_security_group_rule" "node_nodeport_ingress" {
  description       = "NodePort do soat-api (k8s/service.yaml), alcancado direto pelo API Gateway"
  type              = "ingress"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# most_recent = true, equivalente ao que o módulo fazia — resolve a versão
# mais recente compatível com a versão do cluster, em vez do default do EKS.
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = data.aws_eks_addon_version.coredns.version

  depends_on = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.kube_proxy.version

  depends_on = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.vpc_cni.version

  depends_on = [aws_eks_node_group.default]
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "/soat/${var.environment}/eks/cluster-name"
  type  = "String"
  value = aws_eks_cluster.this.name
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name  = "/soat/${var.environment}/eks/cluster-endpoint"
  type  = "String"
  value = aws_eks_cluster.this.endpoint
}
