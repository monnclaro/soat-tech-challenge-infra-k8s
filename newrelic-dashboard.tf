# Dashboard operacional da oficina — atende aos requisitos de observabilidade:
# latência das APIs, consumo de CPU/memória do cluster, healthcheck/uptime,
# volume diário de OS, tempo por fase (funil de status) e erros de integração.
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

    widget_funnel {
      title  = "Ordens de serviço por fase (Recebida → Entregue)"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        # A app loga (Serilog, JSON) "OrdemServicoStatusAlterado {idOrdemServico}
        # {status}" a cada transição de status (OrdemServico.Inserir,
        # IniciarDiagnostico, FinalizarDiagnostico, AprovarOrcamento, Finalizar,
        # Entregar — ver OrdemServicoStatusAlteradoLogHandler no repo da app),
        # sem calcular duração no código e sem depender de NewRelic.Api.Agent/
        # RecordCustomEvent. O nri-bundle (newrelic.tf, logging.enabled = true)
        # já coleta e parseia os logs JSON dos pods, promovendo cada propriedade
        # nomeada do template a um atributo de Log consultável via NRQL. O tempo
        # entre fases é o que o funnel() calcula a partir do timestamp de cada
        # log, correlacionado por idOrdemServico — nenhum timestamp de "início da
        # fase atual" precisou ser persistido na entidade.
        #
        # Best-effort: sem ambiente aplicado até esta entrega, não há logs reais
        # pra validar contra a UI do New Relic. Conferir nomes de atributo
        # (idOrdemServico/status) e ajustar se necessário assim que houver dados.
        query = <<-EOT
          SELECT funnel(timestamp,
            WHERE status = 'Recebida' AS 'Recebida',
            WHERE status = 'EmDiagnostico' AS 'EmDiagnostico',
            WHERE status = 'AguardandoAprovacao' AS 'AguardandoAprovacao',
            WHERE status = 'EmExecucao' AS 'EmExecucao',
            WHERE status = 'Finalizada' AS 'Finalizada',
            WHERE status = 'Entregue' AS 'Entregue'
          ) FROM Log WHERE idOrdemServico IS NOT NULL FACET idOrdemServico SINCE 30 days ago
        EOT
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
