# soat-tech-challenge-infra-k8s

> Infraestrutura como código (Terraform) do cluster Kubernetes gerenciado (Amazon EKS) compartilhado pelos microsserviços da oficina. Nasceu na Fase 3 (1 aplicação monolítica) e passou a hospedar 3 microsserviços na Fase 4: [os-service](https://github.com/monnclaro/soat-tech-challenge-os-service) · [billing-service](https://github.com/monnclaro/soat-tech-challenge-billing-service) · [execution-service](https://github.com/monnclaro/soat-tech-challenge-execution-service) · **infra-k8s** (este repositório) · [infra-database](https://github.com/monnclaro/soat-tech-challenge-infra-database) · [lambda](https://github.com/monnclaro/soat-tech-challenge-lambda). O monolito original ([soat-tech-challenge](https://github.com/monnclaro/soat-tech-challenge)) permanece como referência histórica das Fases 1-3.

## Propósito

Provisiona a **rede (VPC)** e o **cluster Kubernetes (EKS)** compartilhado pelos 3 microsserviços, com node group escalável e infraestrutura de plataforma comum: observabilidade (New Relic) e mensageria (RabbitMQ, desde a Fase 4). É o único repositório com autoridade sobre a VPC — os demais (infra-database, os-service, billing-service, execution-service, lambda) consomem seus outputs via SSM Parameter Store.

Este repo **não** faz deploy de nenhuma aplicação — isso é responsabilidade de cada repositório de microsserviço, que aplica seus próprios manifests Kubernetes (`k8s/`) contra o cluster já provisionado aqui.

## Tecnologias

| Componente | Tecnologia |
|---|---|
| IaC | Terraform ~> 1.9, módulo `terraform-aws-modules/vpc`; EKS via recursos `aws_eks_*` diretos, não o módulo da comunidade (ver `eks.tf`) |
| Cluster | Amazon EKS 1.31, node group gerenciado (`t3.small`, 2–4 nodes — min 2 desde a Fase 4) |
| Exposição das apps | `Service type=NodePort` por microsserviço (30081/30082/30083) — sem ALB, ver nota de custo |
| Mensageria | RabbitMQ (`bitnami/rabbitmq` Helm chart, 1 réplica) — broker compartilhado entre os 3 microsserviços para a saga |
| Observabilidade | New Relic Kubernetes integration (`nri-bundle` Helm chart) + dashboard + alertas |
| CI/CD | GitHub Actions (credenciais estáticas de sessão — AWS Academy) |

## Nota: AWS Academy e prioridade de custo

Esta infraestrutura foi desenhada para caber no **AWS Academy Learner Lab**, cortando tudo que não é estritamente necessário:

| Removido | Motivo | Substituído por |
|---|---|---|
| NAT Gateway (~$32/mês) | Custo fixo, sem free tier | Nodes do EKS em **subnet pública**, com IP próprio, saindo direto pela Internet Gateway |
| ALB + AWS Load Balancer Controller (~$16-20/mês) | Custo fixo + exigiria IRSA (IAM restrito no Academy) | `Service type=NodePort` — o API Gateway (repo lambda) chama direto o IP público de um node |
| Criação de IAM roles/policies (cluster, node group, IRSA) | Academy bloqueia `iam:CreateRole`/`iam:CreateOpenIDConnectProvider` | Reaproveita a `LabRole` já existente na conta (`var.lab_role_arn`) — sem OIDC provider, sem role própria pro cluster/node group |
| Módulo `terraform-aws-modules/eks/aws` | Declara `data.aws_iam_session_context` incondicional, que precisa de `iam:GetRole` — negado explicitamente pela policy do Academy (`Pvoclabs2`) em toda versão testada (19.x/20.x/21.x), mesmo sem usar o valor | `eks.tf` com recursos `aws_eks_cluster`/`aws_eks_node_group`/`aws_eks_addon` diretos |
| KMS key própria para secrets do cluster | `kms:CreateKey` também costuma estar fora da policy do Academy | Sem `encryption_config` no `aws_eks_cluster` (sem envelope encryption customizada) |
| Autenticação OIDC do GitHub Actions | Exigiria criar um IAM Identity Provider (bloqueado) | Credenciais de sessão estáticas do Academy como GitHub Secrets, atualizadas manualmente a cada sessão do Lab |

Único custo fixo que **não** dá pra remover usando EKS: o control plane (~$0,10/h). Justificativa completa e trade-offs: ADR "Prioridade de custo e AWS Academy" (`soat-tech-challenge/docs/adr`).

## Arquitetura

```
┌─────────────────────────────────── VPC ────────────────────────────────────┐
│                                                                              │
│   Subnets públicas (2 AZs)                    Subnets privadas (2 AZs)     │
│   ┌──────────────────────────┐                ┌───────────────────────┐   │
│   │  EKS Node Group           │                │  RDS (infra-database)  │   │
│   │  (IP público, sem NAT)    │                │  Lambda de auth (repo  │   │
│   │  soat-api pods (NodePort) │                │  lambda) — só tráfego  │   │
│   └──────────────┬───────────┘                │  interno da VPC         │   │
│                  │                             └───────────────────────┘   │
└──────────────────┼──────────────────────────────────────────────────────────┘
                    │
                    ▼
     API Gateway (repo lambda) → HTTP_PROXY direto pro
     IP público do node + NodePort (ver README do repo lambda)
```

Publica em SSM: `/soat/producao/network/vpc-id`, `/soat/producao/network/private-subnet-ids`, `/soat/producao/network/vpc-cidr`, `/soat/producao/eks/cluster-name`, `/soat/producao/eks/cluster-endpoint`, `/soat/producao/jwt/secret`, `/soat/producao/rabbitmq/{host,username,password}` (desde a Fase 4 — consumidos pelo CI/CD dos 3 microsserviços para gerar o Secret do deployment).

## Backend remoto

Mesmo bucket S3/DynamoDB do [infra-database](https://github.com/monnclaro/soat-tech-challenge-infra-database#backend-remoto), com `key = "infra-k8s/terraform.tfstate"` — states isolados por repositório, sem leitura cruzada de tfstate (ver ADR de split de infraestrutura).

## Execução

```bash
terraform init
terraform plan \
  -var="lab_role_arn=arn:aws:iam::<account-id>:role/LabRole" \
  -var="new_relic_license_key=..." -var="new_relic_account_id=..." \
  -var="new_relic_api_key=..." -var="new_relic_notification_email=..."
terraform apply -var="lab_role_arn=..." # (+ demais vars acima)

aws eks update-kubeconfig --name soat-producao --region us-east-1
kubectl get nodes
```

`lab_role_arn` não tem default de propósito — pegue o ARN da `LabRole` no painel "AWS Details" do seu Lab do Academy.

## CI/CD

[.github/workflows/terraform.yml](.github/workflows/terraform.yml): PR aciona `plan`, push em `main` aciona `apply` (gated por aprovação manual do GitHub Environment `producao`, que se refere ao ambiente AWS de destino). Segredos necessários: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (do Academy, expiram com a sessão — atualizar antes de cada rodada), `AWS_LAB_ROLE_ARN`, `NEW_RELIC_LICENSE_KEY`, `NEW_RELIC_ACCOUNT_ID`, `NEW_RELIC_API_KEY`, `NEW_RELIC_NOTIFICATION_EMAIL`.

## Observabilidade

Além da integração de infraestrutura (`newrelic.tf`), este repositório provisiona via Terraform (`newrelic-dashboard.tf`, `newrelic-alerts.tf`):

- **Dashboard** "SOAT — Oficina": latência das APIs, taxa de erro por rota, CPU/memória dos nodes, disponibilidade da API, volume diário de ordens de serviço, tempo médio por status e erros no webhook de orçamento.
- **Alertas** (e-mail via `newrelic_workflow`): nenhum pod da API disponível, taxa de erro alta em rotas de Ordem de Serviço, falhas no webhook de orçamento.

Sem ALB/domínio público fixo, o "uptime" é medido por proxy (contagem de pods prontos + taxa de sucesso das transações do APM), não por um Synthetics Monitor HTTP tradicional — ver comentários em `newrelic-alerts.tf`.

## Mensageria (Fase 4)

`rabbitmq.tf` provisiona um único broker RabbitMQ (`bitnami/rabbitmq`, namespace `rabbitmq`, 1 réplica — sem alta disponibilidade, projeto acadêmico) compartilhado pelos 3 microsserviços para a saga orquestrada da Ordem de Serviço. Credenciais geradas via `random_password` e publicadas em SSM (`/soat/producao/rabbitmq/*`), no mesmo padrão do segredo JWT (`jwt.tf`) — cada microsserviço lê de lá no seu próprio deploy para montar o Secret do deployment.

## Links

- Diagrama de componentes completo e ADRs: [soat-tech-challenge/docs](https://github.com/monnclaro/soat-tech-challenge/tree/main/docs)
