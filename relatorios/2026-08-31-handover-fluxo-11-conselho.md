# Handover — Fluxo 11 (Conselho) — para sessão dedicada

Escrito em 2026-08-31. Autossuficiente: esta sessão NÃO vai tocar o fluxo 11 —
o Luís destacou-o da fila para uma sessão dedicada onde **Codex CLI e Gemini CLI
já estão configurados**. Todo o resto da fila (3, 9, 5, 6+7, 8, 10, 4) continua
na sessão principal; não toque nos outros fluxos daqui.

## O pedido

Implementar o fluxo 11 — `conselho.cjs`, debate estruturado de decisões de
design — pelo método rainforest completo: **plano → executar → revisar →
verificar → fechar com PR** (o design já está aprovado; ver abaixo). Branch
própria (`fluxo/conselho`), nascida da ponta da `origin/main` do momento em que
o trabalho começar. Destino de branch é sempre PR — não perguntar.

## O que já está decidido (não reabrir)

- **Design aprovado:** `docs/rainforest/design/fluxo-11-design-conselho.md`
  (141 linhas — leia inteiro antes do plano). Proposta B aprovada em 2026-08-29.
- **Q1 FECHADA em 2026-08-31:** conselho é **passo opcional do estágio `design`**,
  ativado pela presença de `.rainforest/conselho/` (padrão opt-in das rubricas) —
  NÃO é fluxo independente no grafo. Registrado no fim do próprio design doc.
- **Origem e atribuição:** ideias mineradas de karpathy/llm-council, que **não
  tem licença** — nenhuma linha de código pode ser reaproveitada, só as ideias
  (revisão cruzada anonimizada, ranking cruzado, síntese por chairman), com
  atribuição obrigatória no cabeçalho de `conselho.cjs` e no doc.
- **Mecanismo em 3 fases** (pareceres → revisão anonimizada → síntese), tudo
  JSON em `.rainforest/conselho/<id-rodada>/`, com reprovação por exit code:
  `objecoes: []` reprova (defesa contra convergência Claude-com-Claude),
  ranking incompleto reprova, síntese sem `divergencias_nao_resolvidas` (e sem
  `--unanime` explícito) reprova, 3ª tentativa na mesma fase = ABANDONA.
- **Personas v1:** `cetico`, `arquiteto`, `usuario-final`. Persona é papel
  (agente); conhecimento de domínio vem de skill.
- **Contrato de membro:** executável declarado em config (`{nome, cmd}` com
  placeholders `{prompt}`/`{saida}`), spawn com shell por plataforma, Windows
  é requisito. JSON inválido reprova apontando o campo.

## A única decisão nova para o Luís (Q1 desta sessão)

O design diz "**v1: só o adaptador Claude**; codex/gemini entram depois como
integração opcional declarável". Mas o Luís configurou Codex e Gemini CLI
**exatamente na sessão que vai executar isto** — sinal de que ele quer os três
membros de verdade.

**Q1 — escopo da v1: (recomendada) incluir os adaptadores `codex exec` e
`gemini -p` já na v1** como integrações declaráveis desligadas por padrão
(mesmo padrão `integracao-*` do `hooks/lib/config.cjs` + `scripts/setup.cjs`
que o fluxo 3 acabou de criar — use-o como referência), com o adaptador Claude
como único ligado por padrão; **ou (b)** seguir o design à letra (só Claude,
externos depois). Confirme com ele antes do plano.

## Dependências — estado real em 2026-08-31

- `estado.cjs` (fluxo 1): **na main**, endurecido — `marcar --status ok` do
  executar exige ledger de `mutacao` (lista com um item por tarefa do plano,
  tarefas numeradas `### N.`), o `exigir revisar` tira snapshot de HEAD+sujeira
  e o `marcar revisar ok` recusa se o repo mutou ou se faltarem `base`/`head`
  no `--json`. Trabalhe COM as travas, não contra.
- Fluxo 7 (`nao_provado`): **não implementado** — o design do 11 só reutiliza o
  PADRÃO do campo (`divergencias_nao_resolvidas`), não há código a esperar.
- Fluxo 6 (portões): **não implementado** — o 11 declara os portões em rascunho
  (tabela no design), não depende do motor.
- Fluxo 3 (ponte): fechando na sessão principal — se precisar do padrão de
  integração declarável, a referência é `hooks/lib/integracoes.cjs`,
  `hooks/lib/config.cjs` (chaves `integracao-*`) e `scripts/setup.cjs` na
  branch `fluxo/ponte` (ou na main, quando o PR fechar).

## Como trabalhar (protocolo que salvou 8 rodadas nesta sessão)

1. **Estágios pelo `estado.cjs`:** `exigir --estagio <x>` antes, `marcar` depois.
   Crie o estado da rodada com o slug do design.
2. **Plano com tarefas numeradas** (`### 1.`, `### 2.`…) cada uma com `arquivos:`,
   `mutacao:` (arquivo/de/para/bateria/fixture) e "pronto quando" falsificável.
   O "Pronto quando" do design (7 itens) já é meio caminho.
3. **Executor em worktree** (`isolation: "worktree"`), briefing com o hash de
   base esperado e ordem de PARAR se divergir. Worktree falha de 3 modos: não
   cria, cria da base errada (ponta da main), some após o spawn. Contingência
   autorizada: se HEAD for ancestral da base esperada E worktree limpo,
   `git merge --ff-only <hash>` e re-conferir.
4. **Integração valida na saída real** (regra 12): re-rodar baterias no worktree
   E na árvore integrada, exit capturado SEM pipe (`OUT=$(cmd 2>&1); echo $?` —
   pipe devolve o exit do `tail`), re-rodar `conferir-mutacao.cjs` com os
   valores DO PLANO, `conferir-entrega.cjs --worktree --base --head-antes
   --sujo-antes --paralelo` com porcelain capturado ANTES do despacho.
5. **Revisor zerado por rodada** (`rainforest-mind:revisor`, nunca fork),
   briefing com base/head e diff de três pontos. Reproduza TODO achado antes
   de aceitar o veredito. Nesta sessão, 8 revisores acharam 8 defeitos reais
   que 300+ testes verdes não viam — a lição recorrente: **teste verde não é
   evidência; menção/posição de marcador, tipo de entrada e caminho relativo
   são as famílias que mais escaparam**.
6. **Padrões de fabricação de agente já vistos:** teste desligado como conserto
   (`if false`), falha reclassificada "pré-existente" sem baseline, catraca
   "preparada mas não rodada", mutação rodada com script próprio em vez do
   `conferir-mutacao.cjs`, `git show` decorado com hash inventado. A honestidade
   do relato não é evidência.

## Armadilhas específicas do 11

- **Anonimização é função do script**, não instrução de prompt — embaralhar e
  renomear (membro-A/B/C) antes da fase 2, e o teste tem de provar que a
  identidade não vaza (ex.: grep do nome da persona nos arquivos da fase 2).
- **Chairman é mecânico:** agregação de ranking (posição média, desempate por
  1ºs lugares) é código puro e testável sem modelo nenhum — separe isso do
  passo de redação para a bateria não depender de LLM.
- **Baterias não podem depender de CLI externo instalado:** o contrato de
  membro aceita qualquer executável — nos testes, o membro é um **script
  fixture** que escreve JSON conhecido (bom e ruim). Codex/gemini reais só na
  validação manual final.
- **`/saude`:** seção do conselho (rodadas abertas, ABANDONAs) segue o padrão
  do fluxo 3: item só quando há o que dizer, quebrado é `aviso` (exit 0),
  nunca `alerta`.
- **Zero dependência npm** — `child_process` puro, `path.join` sempre.

## Ambiente da sessão dedicada

- Codex CLI e Gemini CLI configurados pelo Luís (autenticação já feita).
  Verifique com `codex --version` / `gemini --version` antes de assumir; regra
  14: bloqueio de ambiente se anuncia em uma linha.
- Commit sempre antes de encerrar a sessão (o Luís já perdeu trabalho).
- Ao fechar: PR, e atualizar este handover com o estado real.
