# Alertas: falhas no processamento de ordens de serviço, healthcheck/uptime
# e erro geral da API — notificando por e-mail via o fluxo moderno de
# Workflows do New Relic (policy → condition → workflow → destination/channel).

resource "newrelic_alert_policy" "soat" {
  name                = "soat-${var.environment}"
  incident_preference = "PER_CONDITION_AND_TARGET"
}

# ── Healthcheck / uptime ──────────────────────────────────────────────────
# Sem ALB/domínio público fixo nesta configuração de custo mínimo (a app é
# exposta via NodePort, cujo IP pode mudar), então não dá pra apontar um
# Synthetics Monitor HTTP pra ela de forma estável. Uso o número de pods
# prontos do Deployment como proxy de uptime — se cair a zero, a API está
# fora do ar. Ver ADR 0008.
resource "newrelic_nrql_alert_condition" "uptime" {
  policy_id = newrelic_alert_policy.soat.id
  type      = "static"
  name      = "Nenhum pod da API disponível"

  nrql {
    query = "SELECT uniqueCount(podName) FROM K8sPodSample WHERE clusterName = 'soat-${var.environment}' AND deploymentName = 'soat-api' AND status = 'Running'"
  }

  critical {
    operator              = "below"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }

  fill_option = "static"
  fill_value  = 0
}

# ── Falhas no processamento de ordens de serviço ───────────────────────────
resource "newrelic_nrql_alert_condition" "erro_ordem_servico" {
  policy_id = newrelic_alert_policy.soat.id
  type      = "static"
  name      = "Taxa de erro alta em Ordens de Serviço"

  nrql {
    query = "SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = 'soat-api' AND name LIKE '%OrdemServico%'"
  }

  critical {
    operator              = "above"
    threshold             = 5
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }

  warning {
    operator              = "above"
    threshold             = 2
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

# ── Falhas na integração de orçamento (webhook) ────────────────────────────
resource "newrelic_nrql_alert_condition" "erro_webhook_orcamento" {
  policy_id = newrelic_alert_policy.soat.id
  type      = "static"
  name      = "Falha no webhook de orçamento"

  nrql {
    query = "SELECT count(*) FROM Transaction WHERE appName = 'soat-api' AND name LIKE '%OrcamentoWebhook%' AND error IS true"
  }

  critical {
    operator              = "above"
    threshold             = 3
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

# ── Notificação por e-mail ──────────────────────────────────────────────
resource "newrelic_notification_destination" "email" {
  name = "soat-${var.environment}-email"
  type = "EMAIL"

  property {
    key   = "email"
    value = var.new_relic_notification_email
  }
}

resource "newrelic_notification_channel" "email" {
  name           = "soat-${var.environment}-email"
  type           = "EMAIL"
  destination_id = newrelic_notification_destination.email.id
  product        = "IINT"

  property {
    key   = "subject"
    value = "[SOAT ${upper(var.environment)}] {{issueTitle}}"
  }
}

resource "newrelic_workflow" "soat" {
  name                  = "soat-${var.environment}"
  enrichments_enabled   = false
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "soat-${var.environment}-policy-filter"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.soat.id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email.id
  }
}
