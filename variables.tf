variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  description = "Ambiente de deploy. Só existe 'producao' nesta fase — sem homologação, para minimizar custo (AWS Academy)."
  type        = string
  default     = "producao"

  validation {
    condition     = var.environment == "producao"
    error_message = "environment deve ser 'producao' — não há ambiente de homologação nesta fase."
  }
}

variable "lab_role_arn" {
  description = <<-EOT
    ARN da role IAM já existente na conta AWS Academy (normalmente "LabRole"),
    usada para o cluster EKS e o node group. O Academy bloqueia criação de
    roles/policies IAM novas, então não criamos nenhuma — só reaproveitamos
    esta. Consulte em Academy > "AWS Details" > IAM.
  EOT
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones usadas pela VPC (2 é o mínimo para o EKS)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "cluster_version" {
  description = "Versão do Kubernetes no EKS."
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "t3.small (não t3.medium) por padrão — metade do custo por node, ainda suficiente pros pods deste projeto. Confirme se o Academy libera esse tipo de instância."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "new_relic_license_key" {
  description = "License key do New Relic (New Relic Kubernetes integration). Sensível — vem de TF_VAR_new_relic_license_key no CI."
  type        = string
  sensitive   = true
}

variable "new_relic_account_id" {
  type = string
}

variable "new_relic_api_key" {
  description = "User API key do New Relic (NRAK-...), usada para criar dashboards e alertas via Terraform. Diferente da license key do agente."
  type        = string
  sensitive   = true
}

variable "new_relic_notification_email" {
  description = "E-mail que recebe os alertas (falhas de OS, cluster indisponível)."
  type        = string
}
