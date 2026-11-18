# Workshop DVN · 14 e 15 de novembro

Simulador de carga do workshop **DevOps na Nuvem (DVN)**. Um e-commerce de demonstração recebe milhares de pedidos de Black Friday e deixa à mostra cada peça da arquitetura serverless: onde o pedido entra, onde ele espera e onde o estoque é atualizado.

O painel React (hospedado em S3 + CloudFront) inicia execuções no API Gateway. A Lambda de **controle** prepara o estoque no DynamoDB e aciona as Lambdas **geradoras**, que disparam chamadas HTTP ao API Gateway durante a janela configurada. O API Gateway publica os pedidos no SQS FIFO e devolve `202`. A Lambda **processadora** consome a fila em paralelo e registra a baixa no estoque com uma transação no DynamoDB.

> `202` confirma apenas que o SQS aceitou o pedido. O estoque é abatido depois, de forma assíncrona.

## Arquitetura

```mermaid
flowchart LR
    A["Painel<br/>CloudFront + S3"] -->|POST /runs · GET /runs/{id}| B["Controller<br/>Lambda"]
    B --> C[("DynamoDB<br/>metadados + estoque")]
    B -->|Invoke assíncrona| D["Generators<br/>Lambda"]
    D -->|POST /orders| E[API Gateway]
    E -->|202 · SendMessageBatch| F[SQS FIFO]
    F --> G["Processor<br/>Lambda"]
    G -->|transação| C
```

- **1.024 grupos FIFO** e **1.024 partições lógicas de estoque** por execução, para que um único contador não vire o gargalo.
- Cada pedido consome 1 unidade de estoque; uma partição esgotada rejeita pedidos mesmo com saldo em outra.
- Reentregas do SQS são deduplicadas por **7 dias** no DynamoDB (marcadores idempotentes).

Guias de apoio: [Guia do workshop](site/public/guia-workshop.html) · [Roteiro do Console AWS](site/public/roteiro-console.html)

## Estrutura do projeto

```
.
├── backend/                # Funções Lambda (TypeScript, runtime nodejs26.x)
│   ├── lambda-controller/  # Inicia execuções e monta o relatório (API Gateway)
│   ├── lambda-generator/   # Envia pedidos ao API Gateway durante a janela
│   ├── lambda-processor/   # Consome o SQS e atualiza o estoque (transação)
│   ├── shared/             # Tipos, domínio, acesso ao DynamoDB, lotes, latência
│   └── tests/              # Testes de unidade (node --test)
├── site/                   # Painel React + Vite
├── infra/                  # Infraestrutura como código (Terraform)
│   └── modules/backend/   # S3, CloudFront, Lambda, SQS FIFO, DynamoDB, IAM
├── k6-load-test/           # Teste de carga com k6 e gerador local em Go
├── buildspec.yaml          # Pipeline CodeBuild (build + Terraform)
└── parameters.py           # Gera .tfvars a partir do SSM Parameter Store
```

## Pré-requisitos

- **Node.js 22.18** ou superior para rodar o painel localmente (o pipeline empacota as Lambdas com Node 26).
- Conta AWS própria, com permissão para criar os recursos.
- Para o teste de carga: **k6** (e **Go**, caso use o gerador local).
- Para o deploy via pipeline: **Terraform ≥ 1.15.0** e o AWS CLI.

## Montagem manual no Console AWS

Use o [roteiro do Console AWS](site/public/roteiro-console.html) para criar os recursos e empacotar as Lambdas passo a passo: DynamoDB e filas FIFO, build/ZIP das Lambdas, variáveis de ambiente, API Gateway e rotas, integrações com SQS, headers/CORS/API key, S3 + CloudFront, e uma tabela de dimensionamento de 100 mil a 1 milhão de pedidos.

Os arquivos `.env.example` de cada função descrevem as variáveis que você configura no Console. Use sua própria conta, endpoint e chave da API.

### Rodar o painel localmente

```bash
npm --prefix backend ci
npm --prefix backend run build
npm --prefix site ci
npm --prefix site run dev
```

Na aba **Conexão & execução** do painel, informe a URL do seu stage do API Gateway e a chave do seu laboratório.

### Gerar os estáticos para o S3

```bash
npm --prefix site run build
```

A saída fica em `site/dist/`.

## Deploy com Terraform (pipeline)

O repositório inclui infraestrutura como código em `infra/` e um pipeline no `buildspec.yaml` para o AWS CodeBuild. O pipeline:

1. Instala o Terraform (cacheado em S3) e executa `parameters.py`, que lê um parâmetro no **SSM Parameter Store** e gera o `<ambiente>.tfvars`.
2. Empacota o **site** (`npm install` + `npm run build`).
3. Empacota as **Lambdas**: `npm ci`, `npm run build`, `npm prune --omit=dev` e cria os zips em `backend/dist/`.
4. Executa `terraform init`, `terraform validate` e `terraform <comando>` (`apply` por padrão).

O módulo `infra/modules/backend` provisiona: bucket S3 + distribuição CloudFront (com Origin Access Control), as três funções Lambda (`nodejs26.x`), fila SQS FIFO com DLQ, tabela DynamoDB e roles/policies IAM.

Variáveis principais em `infra/_variables.tf`: `region`, `environment`, `organization_name`, `application_name`, `account_client` e `common_tags`.

## Teste de carga

O `k6-load-test/` envia pedidos ao API Gateway. O `run.sh` orquestra os modos e recompila o backend automaticamente quando necessário.

Configure um perfil AWS com acesso à tabela do laboratório e preencha `k6-load-test/.env`:

```bash
cp k6-load-test/.env.example k6-load-test/.env
```

| Comando | Descrição |
| --- | --- |
| `./k6-load-test/run.sh <requisições> <segundos>` | Execução simples com k6 (ex.: `1000 60`) |
| `./k6-load-test/run.sh local <requisições> <segundos>` | Gerador local em Go (precisa do Go no PATH) |
| `./k6-load-test/run.sh prepare <requisições>` | Só prepara o estoque e devolve o `runId` |
| `./k6-load-test/run.sh status <runId>` | Consulta o estoque de uma execução |
| `./k6-load-test/run.sh plan <req> <seg> <executores> <antecedência_s>` | Simula um plano distribuído sem preparar estoque |
| `./k6-load-test/run.sh prepare-distributed <...>` | Prepara o estoque e grava um plano em `reports/` |
| `./k6-load-test/run.sh worker <plano.json> <nº executor>` | Executa um executor do plano distribuído |

O script solicita a chave da API no terminal quando `API_KEY` não está configurada. Os relatórios ficam em `k6-load-test/reports/`. Para consultar todas as opções:

```bash
./k6-load-test/run.sh --help
```

## Configuração de uma execução

Cada execução valida os limites abaixo (definidos em `backend/shared/domain.ts`):

| Parâmetro | Intervalo | Descrição |
| --- | --- | --- |
| `total` | inteiro ≥ 1 | Total de pedidos da execução |
| `duration` | 1 a 600 s | Janela de envio |
| `stock` | 0 a 10.000.000 | Estoque inicial |
| `workers` | 1 a 100 | Quantidade de geradores Lambda |
| `sendMode` | `single` \| `batch` | 1 pedido por chamada HTTP, ou até 10 por `SendMessageBatch` |

- **1.024 shards** por execução (grupos FIFO + partições de estoque).
- O painel calcula a quantidade de workers para a taxa desejada (meta: 30 chamadas HTTP/s por worker no modo em lote).
- Itens do DynamoDB expiram em 7 dias (TTL).

## Variáveis de ambiente

Cada função tem um `.env.example` de referência (valores configurados no Console ou via Terraform):

- **lambda-controller** — `TABLE`, `GENERATOR`, `QUEUE`, `DLQ`
- **lambda-generator** — `TABLE` (URL e chave da API chegam no evento enviado pela controller)
- **lambda-processor** — `TABLE` (batch size e concorrência são configurações do gatilho SQS)
- **site** — `VITE_API_URL` (URL base do stage do API Gateway)
- **k6-load-test** — `AWS_PROFILE`, `AWS_REGION`, `TABLE`, `API_URL`, `API_KEY`

## Testes automatizados

```bash
npm --prefix backend test
```

Roda o build e os testes de `backend/tests/` com `node --test`.
