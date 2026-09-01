# Regra 10 — portaria

A admissão de subagente por manifesto (fluxo 9), separada de `regra-10.md` em
2026-09-01 pelo mesmo motivo que partiu a regra 12: a regra e o histórico dela
cresceram juntos e estouraram o teto de bytes de um `reference`. A regra em si —
roteamento por função, limiar de 3.000 tokens, agente que edita não é nomeado —
continua em `regra-10.md`.

Com a portaria registrada (ver 'Estado atual' abaixo), subagente só roda se estiver declarado em `.rainforest/agentes.json` com o estágio ativo na sua lista. A decisão é tomada por código (hook `PreToolUse` que intercepta a tool `Task`), nunca por pergunta ao humano em runtime.

> **Regra 10 (reescrita):** Subagente só roda se estiver declarado em `.rainforest/agentes.json` e o estágio ativo constar na sua lista. A portaria decide por código; o humano nunca é perguntado em sessão. Exceção não existe em runtime — exceção é editar o manifesto, e edição de manifesto é mudança versionada que passa pelo `revisar`.

**O manifesto** (`.rainforest/agentes.json`) declara por agente:
- `estagios`: em quais estágios do grafo (ex.: `["revisar"]`, `["design", "plano"]`) pode ser despachado.
- `escreve`: por ora, sempre `false` — subagente não escreve, só relata.

Exemplo:
```json
{
  "versao": 1,
  "agentes": {
    "revisor":    { "estagios": ["revisar"], "escreve": false },
    "planejador": { "estagios": ["design", "plano"], "escreve": false }
  }
}
```

**Fail-closed, sempre com motivo.** A portaria nega quando: manifesto ausente ou inválido (JSON malformado ou `versao` desconhecida), agente não declarado, sem estágio ativo (nenhum fluxo aberto que case com a branch), estágio ativo fora da lista `estagios` do agente, ou `escreve: false` mas o arquivo `agents/<nome>.md` declara tools fora da allowlist read-only (`Read`, `Grep`, `Glob`). Toda negação sai com motivo não vazio — negação muda é bug.

**Log de despacho** (`.rainforest/portaria/despachos.jsonl`): append-only, uma linha JSON por decisão, aprovada ou negada. Cada linha é autocontida — legível isolada, sem precisar do resto do log para fazer sentido:
```json
{"ts":"2026-08-31T14:02:11Z","agente":"revisor","estagio":"revisar","decisao":"allow","sessao":"<id>"}
{"ts":"2026-08-31T14:05:47Z","agente":"executor","estagio":"revisar","decisao":"deny","motivo":"agente 'executor' não consta no manifesto","sessao":"<id>"}
```

O log é evidência de primeira classe: responde "quem rodou, quando, em qual estágio" com `cat`, e o recibo do fluxo 7 pode referenciá-lo. Entra no `.gitignore` (tarefa 4 do plano) — `.rainforest/agentes.json` e `.rainforest/portaria/amostra.json` ficam versionados (documentação); o log de execução não.

**Exceção é editar o manifesto.** Quem quer disparar agente não declarado edita `.rainforest/agentes.json`, passando a mudança pelo `revisar` — é o único jeito de aprovar novas declarações. Em runtime, sem edição no manifesto, não há pergunta ao humano.

**Estado atual (Opção A: 2026-08-31).** Enquanto `escreve: false` for a única opção no schema e agentes escritores (`executor`, `documentador`, `resolvedor-de-build`, `tester`) não tiverem worktree próprio (extensão futura não implementada), esses quatro agentes não cabem no manifesto real — ficar de fora do manifesto significa serem bloqueados assim que o hook for registrado em `.claude/settings.json`. A Tarefa 9 do plano (fluxo 9) registra bloqueio explícito — o hook entra em produção (`main`) apenas com aceite por escrito do usuário de que sabe e aceitou que `executor`/`documentador`/`resolvedor-de-build`/`tester` param de rodar nesse instante, até a reavaliação futura de `escreve: true` com isolamento de worktree.

**Aceite registrado (Luís, 2026-09-01).** A Opção A foi aceita: `executor`, `documentador`, `resolvedor-de-build` e `tester` param de rodar quando o hook entrar na `main`, até a reavaliação de `escreve: true` com worktree por filho. O manifesto real admite três — `revisor` e `auditor-de-seguranca` em `["revisar"]`, `planejador` em `["design", "plano"]`. `arqueologo` fica de fora porque escreve em `docs/rainforest/mapas/`; `depurador`, por não ter sido avaliado.

**Dívida nomeada: `escreve: false` é declaração, não trava.** A decisão 6 (runtime) e a checagem 3 (lint) leem `tools:` do frontmatter e negam o que estiver fora de `Read`/`Grep`/`Glob`. Ela não dispara contra agente real, por duas portas:

1. **Nenhum** dos nove arquivos em `agents/` declara `tools:` (medido em 2026-09-01) — todos herdam o conjunto inteiro. Escrever `tools: Read, Grep, Glob` nos três admitidos foi recusado com razão: o `revisor` precisa de `Bash` para **reproduzir cada achado** antes do veredito, que é o que a regra 12 cobra dele. A trava real exigiria uma allowlist que separasse "roda comando" de "escreve arquivo", e o frontmatter não tem isso.
2. Em repositório que apenas **consome** o plugin, o arquivo do agente nem existe localmente — vem do cache. A portaria então aprova sem conferir, e tem de aprovar: negar por arquivo ausente quebraria a portaria fora deste repo. O `--lint` diverge de propósito, porque ele é local a este repositório, onde todo agente declarado tem de ter arquivo.

A assimetria é desenho. O que estava errado, e a rodada 4 da revisão pegou, é ela ser **invisível**: o allow saía idêntico ao de um agente conferido. Agora a linha do `despachos.jsonl` traz `escreve_conferido: false` quando a checagem não pôde ser feita — allow sem o campo é allow conferido. Até a folga fechar, quem defende é o manifesto + estágio, não o `escreve`.
