# Cluster EKS com node group gerenciado e escalabilidade (o HPA, provisionado
# pelo repo da aplicação, escala os pods dentro do node group).
#
# IAM restrito (AWS Academy): não criamos nenhuma role — cluster e node group
# reaproveitam a LabRole já existente na conta (var.lab_role_arn). Por isso
# também: enable_irsa = false (criar o OIDC provider é uma ação de IAM
# bloqueada no Academy) e sem KMS key própria para envelope encryption dos
# Secrets do cluster (kms:CreateKey também costuma estar fora da policy do
# Academy). Ver ADR 0008.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "soat-${var.environment}"
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  create_iam_role = false
  iam_role_arn    = var.lab_role_arn

  enable_irsa               = false
  create_kms_key            = false
  cluster_encryption_config = {}

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      create_iam_role = false
      iam_role_arn    = var.lab_role_arn

      labels = {
        workload = "soat-api"
      }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  tags = {
    Ambiente = var.environment
  }
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "/soat/${var.environment}/eks/cluster-name"
  type  = "String"
  value = module.eks.cluster_name
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name  = "/soat/${var.environment}/eks/cluster-endpoint"
  type  = "String"
  value = module.eks.cluster_endpoint
}
