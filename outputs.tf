output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl local contra o cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}
