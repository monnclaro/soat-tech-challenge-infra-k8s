# VPC única (produção). Consumida por soat-tech-challenge-infra-database e
# soat-tech-challenge-lambda via SSM — ver README.
#
# Sem NAT Gateway (~$32/mês) de propósito — prioridade de custo (AWS Academy).
# Os nodes do EKS ficam em subnet PÚBLICA, com IP público próprio, saindo
# direto pela Internet Gateway (sem precisar de NAT). RDS e o Lambda de auth
# continuam em subnet privada — não precisam de rota de saída pra internet,
# só de alcançar recursos dentro da própria VPC. Ver ADR 0008.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "soat-${var.environment}"
  cidr = var.vpc_cidr
  azs  = var.azs

  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
  enable_dns_hostnames    = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/soat-${var.environment}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/soat-${var.environment}" = "shared"
  }
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/soat/${var.environment}/network/vpc-id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/soat/${var.environment}/network/private-subnet-ids"
  type  = "StringList"
  value = join(",", module.vpc.private_subnets)
}

resource "aws_ssm_parameter" "eks_node_sg_id" {
  name  = "/soat/${var.environment}/network/eks-node-sg-id"
  type  = "String"
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# Publicado para o infra-database liberar 5432 por CIDR (em vez de por SG
# específico) — assim RDS não precisa conhecer o SG do EKS nem de um futuro
# consumidor (ex.: o Lambda de autenticação), qualquer recurso dentro das
# subnets privadas da VPC já tem acesso de rede.
resource "aws_ssm_parameter" "vpc_cidr" {
  name  = "/soat/${var.environment}/network/vpc-cidr"
  type  = "String"
  value = var.vpc_cidr
}
