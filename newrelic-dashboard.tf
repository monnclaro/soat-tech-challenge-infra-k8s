# Dashboard operacional da oficina — atende aos requisitos de observabilidade:
# latência das APIs, consumo de CPU/memória do cluster, healthcheck/uptime,
# volume diário de OS, tempo médio de execução por status e erros de integração.
# NRQL assume: (a) o app reporta como "soat-api" no APM (NEW_RELIC_APP_NAME,
# ver k8s/configmap.yaml no repo da aplicação); (b) o nri-bundle (newrelic.tf)
# está enviando K8sContainerSample para este cluster.

resource "newrelic_one_dashboard" "operacional" {
  name = "SOAT — Oficina (${var.environment})"

  page {
    name = "APIs e Kubernetes"

    widget_line {
      title  = "Latência média das APIs (soat-api)"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT average(duration) * 1000 AS 'Latência (ms)' FROM Transaction WHERE appName = 'soat-api' TIMESERIES"
      }
    }

    widget_line {
      title  = "Erros por rota (taxa de erro %)"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = 'soat-api' FACET name TIMESERIES"
      }
    }

    widget_line {
      title  = "CPU dos nodes do cluster"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT average(cpuUsedCores) FROM K8sNodeSample WHERE clusterName = 'soat-${var.environment}' TIMESERIES"
      }
    }

    widget_line {
      title  = "Memória dos nodes do cluster"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT average(memoryUsedBytes) / 1e6 AS 'MB' FROM K8sNodeSample WHERE clusterName = 'soat-${var.environment}' TIMESERIES"
      }
    }

    widget_billboard {
      # Sem domínio público fixo nesta configuração de custo mínimo (app
      # exposta via NodePort) — uso taxa de sucesso das transações do APM
      # como proxy de disponibilidade, em vez de um Synthetics Monitor HTTP.
      title  = "Disponibilidade da API (taxa de sucesso, 24h)"
      row    = 7
      column = 1
      width  = 4
      height = 3

      nrql_query {
        query = "SELECT percentage(count(*), WHERE error IS false) FROM Transaction WHERE appName = 'soat-api' SINCE 1 day ago"
      }
    }

    widget_billboard {
      title  = "Pods em execução"
      row    = 7
      column = 5
      width  = 4
      height = 3

      nrql_query {
        query = "SELECT uniqueCount(podName) FROM K8sPodSample WHERE clusterName = 'soat-${var.environment}' AND deploymentName = 'soat-api' SINCE 5 minutes ago"
      }
    }
  }

  page {
    name = "Ordens de Serviço"

    widget_bar {
      title  = "Volume diário de ordens de serviço"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM Transaction WHERE appName = 'soat-api' AND name LIKE '%OrdemServico%' AND http.method = 'POST' FACET dateOf(timestamp) SINCE 30 days ago"
      }
    }

    widget_table {
      title  = "Tempo médio de execução por status (Diagnóstico, Execução, Finalização)"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        # PENDENTE DE INSTRUMENTAÇÃO: a entidade OrdemServico já guarda
        # DataCriacao/DataInicioExecucao/DataFinalizacao, mas nenhum lugar do
        # código hoje emite um evento customizado do New Relic com essa
        # duração. Este widget assume um evento "OrdemServicoStatusAlterado"
        # (atributos: status, duracaoSegundos) que precisa ser emitido pela
        # aplicação — ver docs/observabilidade.md > "Gaps conhecidos" no repo
        # da aplicação para o plano de instrumentação.
        query = "SELECT average(duracaoSegundos) FROM OrdemServicoStatusAlterado FACET status SINCE 7 days ago"
      }
    }

    widget_line {
      title  = "Erros e falhas nas integrações (webhook de orçamento)"
      row    = 4
      column = 1
      width  = 12
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM Transaction WHERE appName = 'soat-api' AND name LIKE '%OrcamentoWebhook%' AND error IS true TIMESERIES"
      }
    }
  }
}
