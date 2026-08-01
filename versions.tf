terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.44"
    }
  }

  # Backend remoto — state compartilhado entre execuções de CI/CD (a AWS
  # Academy reseta a conta entre sessões, então bucket/tabela não podem
  # depender de terem sido criados manualmente uma única vez). O workflow
  # (.github/workflows/terraform.yml) cria bucket e tabela se não existirem,
  # antes do terraform init — idempotente, roda em todo PR/push.
  backend "s3" {
    bucket         = "soat-tech-challenge-tfstate"
    key            = "infra-k8s/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "soat-tech-challenge-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Projeto       = "soat-tech-challenge"
      Repositorio   = "soat-tech-challenge-infra-k8s"
      GerenciadoPor = "terraform"
      Ambiente      = var.environment
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "newrelic" {
  account_id = var.new_relic_account_id
  api_key    = var.new_relic_api_key # User API key (NRAK-...), diferente da license key usada pelo nri-bundle
  region     = "US"
}
