# Segredo JWT compartilhado entre app (login por email/senha) e lambda
# (login por CPF) — os dois emitem/validam o mesmo tipo de token.
#
# Criado aqui, não no repo lambda: o bootstrap dos 4 repositórios é uma
# cadeia (infra-k8s → infra-database → app → lambda), e tanto o app quanto
# o lambda leem esse segredo do SSM. Se o lambda fosse o dono, o primeiro
# deploy do app falharia (segredo ainda não existe, porque lambda só aplica
# depois do app) — e o lambda também não conseguiria aplicar antes do app
# (precisa do IP do node, publicado pelo app). Dependência circular. Como
# infra-k8s é o primeiro da cadeia e não depende de mais ninguém, é o único
# lugar onde isso não quebra o bootstrap.
resource "random_password" "jwt_secret" {
  length  = 48
  special = false # apenas alfanumérico: evita escaping ao injetar como env var
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/soat/${var.environment}/jwt/secret"
  type  = "SecureString"
  value = random_password.jwt_secret.result
}
