# Plano: Agente auditor de API contra OWASP API Security Top 10 2023

Design: docs/rainforest/design/2026-08-24-auditor-de-api-owasp.md

## O que não pode quebrar

- O orçamento agregado continua **abaixo de 14000 B** (`node scripts/orcamento.cjs` com exit 0). A folga medida antes deste trabalho era 579 B.
- Os 8 agentes existentes continuam com o bloco `perfil-de-trabalho` em sincronia com `referencias/perfil-de-trabalho.md` (`node scripts/perfil.cjs --conferir` com exit 0).
- O estágio `fechar` continua fechando: `scripts/estado.cjs marcar --estagio fechar` continua aceitando os mesmos valores de `acao` que a skill nomeia.
- Nenhum arquivo do `tbc-licensing` é escrito. A validação daquele repositório é **leitura**.
- Nenhuma requisição de rede sai contra endpoint de terceiro.

## Tarefas

### 1. Escrever o agente auditor-de-api [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6, D7, D8, D9
arquivos: `agents/auditor-de-api.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `agents/auditor-de-api.md`
  de: o cabeçalho da categoria `### API7 — Server Side Request Forgery (SSRF)`
  para: o mesmo cabeçalho renomeado para `### API7 — (removida)`, mantendo o corpo
  bateria: `bash scripts/testa-auditor-de-api.sh`
  fixture: `testa-auditor-de-api.sh, o caso "as dez categorias estao presentes e numeradas de API1 a API10"`
pronto quando: com um repositório real que exponha rota por identificador (o `tbc-licensing`), um despacho do agente devolve relatório contendo **uma seção por categoria de API1 a API10**, cada achado com `arquivo:linha` que abre no editor e rótulo `CONFIRMADO`/`INFERIDO`/`LACUNA` — provado pelo despacho da tarefa 5, cujo relatório é anexado ao PR

### 2. Escrever a bateria do agente [tipo: teste]
atende: D2, D4, D6, D9
arquivos: `scripts/testa-auditor-de-api.sh`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: esta tarefa **é** o instrumento; a mutação que prova que ela sabe ficar vermelha está declarada na tarefa 1 e é executada contra `agents/auditor-de-api.md`, não contra este arquivo
pronto quando: com o `agents/auditor-de-api.md` que a tarefa 1 entregou, a bateria confere as dez categorias, o `model: sonnet`, a proibição de consertar e a proibição de mandar requisição — e com a categoria API7 renomeada (mutação da tarefa 1) ela sai **vermelha nomeando API7**, não com erro genérico

### 3. Corrigir os dois defeitos do estágio fechar [tipo: implementar]
atende: D12
arquivos: `skills/fechar/SKILL.md`, `scripts/testa-fechar-destino.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `skills/fechar/SKILL.md`
  de: a lista de palavras-chave de fechamento em inglês do passo 4
  para: a mesma lista acrescida de `Fecha` (a palavra em português que o GitHub ignora, e que deixou #81 e #79 abertas)
  bateria: `bash scripts/testa-fechar-destino.sh`
  fixture: `testa-fechar-destino.sh, o caso "toda palavra-chave nomeada pela skill esta no conjunto que o GitHub honra"`
pronto quando: com o mesmo corpo de PR que falhou em 2026-08-24 ("Fecha #81 e #79"), a bateria classifica esse corpo como **não fechando issue nenhuma**, e classifica `Closes #81, closes #79` como fechando as duas — e o passo 4 da skill não oferece mais "merge local" como escolha do usuário, mantendo os valores de `acao` que o `scripts/estado.cjs` aceita

### 4. Sincronizar o perfil e conferir o orçamento [tipo: configurar]
atende: D1
arquivos: `agents/auditor-de-api.md`, `docs/rainforest/estado/2026-08-24-auditor-de-api-owasp.json`
depende de: 1
paralela: nao
mutacao:
  arquivo: `agents/auditor-de-api.md`
  de: a linha `description:` do frontmatter, com o texto entregue pela tarefa 1
  para: a mesma linha com 900 caracteres de texto, estourando o teto agregado
  bateria: `node scripts/orcamento.cjs`
  fixture: `orcamento.cjs, a assercao de teto agregado de 14000 B (a que decide o exit 1)`
pronto quando: com a sessão real abrindo e o hook injetando o contexto, o total agregado permanece abaixo de 14000 B e o novo agente carrega o bloco `perfil-de-trabalho` idêntico ao de `referencias/perfil-de-trabalho.md` — provado por `node scripts/orcamento.cjs` devolvendo exit 0 com a folga impressa, e por `node scripts/perfil.cjs --conferir` devolvendo exit 0

### 5. Rodar o agente no tbc-licensing e anexar o relatório [tipo: teste]
atende: D10
arquivos: `docs/rainforest/estado/2026-08-24-auditor-de-api-owasp.json`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: é despacho de validação contra repositório de trabalho de terceiro, em leitura; não há linha deste repositório a inverter, e inverter linha do `tbc-licensing` é proibido pelo invariante de leitura
pronto quando: com o `tbc-licensing` no estado em que está hoje, o agente devolve relatório com as dez seções e **pelo menos um achado de API1 (BOLA) ou a declaração explícita de que toda rota por identificador cruza o dono com a identidade do token, citando o `arquivo:linha` da conferência** — e cada `arquivo:linha` citado é reaberto e confere com o que o relatório afirma

### 6. Plantar o que ficou fora do escopo [tipo: docs]
atende: D11
arquivos: `docs/rainforest/estado/2026-08-24-auditor-de-api-owasp.json`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: o plantio grava em `~/.rainforest/ideias.jsonl`, fora deste repositório; não há comportamento deste repo a inverter
pronto quando: com o `ideias.cjs listar` rodando na máquina do usuário, as duas ideias aparecem com `gancho` concreto — a do strix condicionada a alvo em staging próprio, e a da régua de skills condicionada ao repo OWASP sair de Incubator — e o texto de cada uma carrega a medição que a sustenta, não a impressão
