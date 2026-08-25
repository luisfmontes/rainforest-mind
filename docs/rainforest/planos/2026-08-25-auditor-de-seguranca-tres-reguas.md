# Plano: Auditor de segurança com as duas réguas e as cinco falhas do vídeo

Design: docs/rainforest/design/2026-08-25-auditor-de-seguranca-tres-reguas.md

## O que não pode quebrar

- O orçamento agregado continua abaixo de 14000 B (`node scripts/orcamento.cjs`, exit 0). Folga antes desta emenda: 373 B.
- `node scripts/perfil.cjs --conferir` continua exit 0 — o agente renomeado precisa carregar o bloco `perfil-de-trabalho`.
- As baterias já existentes continuam verdes: `scripts/testa-fechar-destino.sh` (34 casos) e a suíte inteira (48 baterias).
- O PR #87 continua sendo **um só**. Esta emenda não abre PR novo.
- Nada é instalado, nenhuma requisição sai contra endpoint de terceiro.

## Tarefas

### 1. Reescrever o agente como auditor-de-seguranca [tipo: implementar]
atende: D1, D2, D3, D4, D6, D7, D8
arquivos: `agents/auditor-de-api.md`, `agents/auditor-de-seguranca.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `agents/auditor-de-seguranca.md`
  de: o cabeçalho `### A10 — Mishandling of Exceptional Conditions`
  para: `### A10 — Insufficient Logging and Monitoring` (o título da edição ANTIGA, que é o erro real que a régua desatualizada produziria)
  bateria: `bash scripts/testa-auditor-de-seguranca.sh`
  fixture: `testa-auditor-de-seguranca.sh, o caso "os dez itens da OWASP Top 10 2025 estao presentes com o titulo da edicao vigente"`
pronto quando: com um repositório que **não** exponha API nenhuma (um CLI, um script que lê arquivo), o agente ainda produz relatório com as dez seções da OWASP Top 10 2025 e as cinco falhas do vídeo endereçadas — isto é, a auditoria não depende mais de existir endpoint, que era o defeito que originou esta emenda

### 2. Escrever a bateria das duas réguas e das cinco falhas [tipo: teste]
atende: D2, D3, D4, D5
arquivos: `scripts/testa-auditor-de-seguranca.sh`, `scripts/testa-auditor-de-api.sh`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: esta tarefa é o instrumento; as mutações que provam que ela sabe falhar estão declaradas nas tarefas 1 e 3 e rodam contra `agents/auditor-de-seguranca.md`
pronto quando: com o `agents/auditor-de-seguranca.md` da tarefa 1, a bateria confere os **dez** títulos da OWASP Top 10 2025 contra a fonte, os **dez** da API Security Top 10 2023, as **cinco** falhas do vídeo nominalmente mapeadas, e as **quatro** ferramentas nomeadas — e com o título de A10 trocado pelo da edição antiga ela sai vermelha **nomeando A10**, não com erro genérico

### 3. Detecção de superfície e declaração do que foi pulado [tipo: implementar]
atende: D5
arquivos: `agents/auditor-de-seguranca.md`
depende de: 1
paralela: nao
mutacao:
  arquivo: `agents/auditor-de-seguranca.md`
  de: a frase que obriga declarar por escrito a régua pulada e o motivo
  para: a mesma frase sem a obrigação (removendo "e o motivo")
  bateria: `bash scripts/testa-auditor-de-seguranca.sh`
  fixture: `testa-auditor-de-seguranca.sh, o caso "regua pulada exige motivo escrito"`
pronto quando: com um repositório sem API, o relatório traz uma seção de superfície detectada dizendo **quais réguas rodaram e qual foi pulada com o motivo** — e não simplesmente omite a régua de API, que é como um agente esconde que trocou o critério por um mais barato (Issue #61)

### 4. Emendar o PR #87 [tipo: docs]
atende: D9, D10
arquivos: `docs/rainforest/estado/2026-08-25-auditor-de-seguranca-tres-reguas.json`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: atualizar título e corpo de um PR no GitHub não tem comportamento local a inverter; a falsificação é o próprio `gh pr view` mostrar o conteúdo novo
pronto quando: com `gh pr list --state open`, existe **exatamente um** PR aberto, de número **87**, cujo corpo descreve as duas réguas e as cinco falhas — e não um PR novo ao lado, que é o que aconteceria se a emenda virasse branch própria
