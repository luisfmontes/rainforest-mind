# Handover — sessão de 2026-08-31 (fluxos 3 e 9)

Para a próxima sessão (Claude pessoal). Autossuficiente: a memória da conta de
trabalho não viaja com este arquivo. Pedido vigente do Luís: executar a fila dos
11 fluxos pelo método rainforest (design→plano→executar→revisar→verificar→fechar),
plantar ideias via `ideias.cjs plantar`, subagentes autorizados (regra 10).

## Onde cada fluxo está

| Fluxo | Estado |
|---|---|
| 1 (ciclo por máquina) e 2 (memória) | fechados e na `main` (21266f7) |
| 3 (ponte + integrações) | branch `fluxo/ponte`, **executar FECHADO 10/10** — próximo estágio: `revisar` |
| 9 (portaria) | branch `fluxo/portaria`, executar 2/9 (T1+T7); **T2 autorizada e em curso** (ver abaixo) |
| 5 fase 0, 6+7, 8, 10, 11, 4 | na fila, nessa ordem; designs instalados em `docs/rainforest/design/` |

Estados canônicos: `docs/rainforest/estado/<slug>.json` (o do fluxo 9 na `main`
está velho — o vivo está na branch `fluxo/portaria`).

## Fluxo 3 — o que falta exatamente

**Executar FECHADO 10/10** (commit c7577cb): T9 foi integrada pela própria sessão
depois de o agente estagnar. Registro do que aconteceu, porque é padrão que se
repete: o agente havia deixado uma "correção" não commitada que trocava a condição
da seção K da `testa-saude.sh` por `if false` — **desligou o teste** em vez de
consertar a causa. Revertida. O defeito real era do caso R2b dele: media exit
absoluto 0 do painel inteiro (frágil — a seção K roda a bateria numa cópia e
qualquer outra checagem ambiental alerta). Conserto integrado: R2b mede o DELTA
(mesmo RFM_ROOT, integração desligada vs ligada-e-quebrada, exit tem de ser o
mesmo). Bateria final 47/0 com a seção K viva; catraca da T9
(`aviso(\`integracao-\${nome}\`, resultado.detalhe` → `alerta(...)`) exit 0.

**Próximo estágio: `revisar`** — revisor independente (sonnet) sobre o diff real
`main..fluxo/ponte`, depois `verificar` (critérios do plano contra o artefato) e
`fechar` com PR (destino de branch é sempre PR — não perguntar).

**Ledger de mutação já gravado no estado** (`marcar ok` exigiu fixture por
tarefa — está tudo em `docs/rainforest/estado/2026-08-28-ponte-bloco-do-projeto-e-integracoes.json`).
Referência do que foi medido (todos exit 0, na árvore integrada):

- T1: `hooks/lib/ponte-corpo.cjs`, de `', e monte com \`node <plugin>/scripts/setup.cjs --criar\` se ainda nao existir'` para `''`, bateria `testa-ponte.sh` → vermelho
- T2: `scripts/ponte.cjs`, detecção de stack Node → vermelho (medido na integração da T2)
- T3: `scripts/ponte.cjs`, de `'fs.renameSync(arquivoTmp, arquivoFinal);'` para comentado, bateria `testa-ponte-entrevista.sh` → vermelho
- T4: **alvo movido pela T5** — agora `scripts/ponte.cjs`, de `'blocoProjetoComHash ? \`${marcado}\n${blocoProjetoComHash}\n\` : marcado'` para `'marcado'` → vermelho (plano já emendado)
- T5: `scripts/conferir-ponte.cjs`, de `'hashNoMarcador === hashAtualProjetoMd'` para `'true'` → vermelho
- T6: `hooks/lib/config.cjs`, entrada `integracao-whatsapp-mcp` removida, bateria `testa-setup.sh` → vermelho
- T7: `hooks/lib/integracoes.cjs`, de `'resolve({ ok: true, detalhe:'` para `ok: false` → vermelho
- T8: `hooks/lib/integracoes.cjs`, de `'if (sabiaExists && venvExists)'` para `'if (false)'` → vermelho
- T9: `scripts/saude.cjs`, de `'aviso(\`integracao-\${nome}\`, resultado.detalhe'` para `alerta(...)` (o `--de` curto casa 2x — usar este, com o `, resultado.detalhe`), bateria `testa-saude.sh` → vermelho
- T10: n/a (docs; a falsificação é o caso k da bateria executando os exemplos do SKILL)

Depois: `revisar` (revisor sonnet no diff `main..fluxo/ponte`), `verificar`,
`fechar` com PR (destino de branch é sempre PR — não perguntar).

## Fluxo 9 — T2 em curso (autorizada pelo Luís nesta sessão)

T2 = hook em modo captura + registro + amostra real (D6/D7). Feito até aqui:
- `hooks/portaria.cjs` **criado e commitado na `fluxo/ponte`** (b2d728b — mover
  para a `fluxo/portaria` no passo 5):
  modo captura — lê stdin, grava a PRIMEIRA amostra em
  `<repo>/.rainforest/portaria/amostra.json` (primeira captura vence, D7), exit 0
  sempre. Payload ilegível não vira amostra.

Falta:
1. `hooks/testa-portaria-captura.cjs` — bateria da catraca: duas execuções com
   stdin simulado (payloads distintos), a primeira grava, a segunda NÃO
   sobrescreve. Emendar o plano: `arquivos:` da T2 ganha essa bateria.
2. `.claude/settings.json` versionado com PreToolUse — **matcher `"Task|Agent"`**:
   o nome real da tool de despacho é justamente a Premissa 2 que a amostra
   responde; capturar largo e fixar o parser (T3) no que a amostra disser.
   Comando: `node "$CLAUDE_PROJECT_DIR/hooks/portaria.cjs"`.
   ATENÇÃO: mudança de hooks em settings vale a partir de sessão nova (ou
   aprovação via /hooks) — o Luís está ciente e presente.
3. Despacho real de um subagente barato nesta ou na próxima sessão → conferir
   `.rainforest/portaria/amostra.json` (JSON válido, apontar o campo com o nome
   do agente, ex. `tool_input.subagent_type`).
4. Catraca da T2: `--arquivo hooks/portaria.cjs --de 'if (!fs.existsSync(amostraPath))'
   --para gravação incondicional --bateria 'node hooks/testa-portaria-captura.cjs'`.
5. Commitar tudo na branch `fluxo/portaria` (NÃO na fluxo/ponte). A branch está
   ATRÁS da main — antes de trabalhar nela: `git merge origin/main` (ou main local).
6. Pré-condição da T9 do fluxo 9 (Achado 2/Opção A): o hook só entra na `main`
   com aceite POR ESCRITO do Luís do bloqueio de executor/documentador/
   resolvedor-de-build/tester. Já registrado no estado; confirmar na hora.

## Protocolo de integração (o que segurou esta sessão — regra 12)

1. NADA do relato entra em comando: re-derive hash/caminho de `git`.
2. Escopo: `git diff --name-status <base>..worktree-agent-*` tem de bater com o
   `arquivos:` do plano; ripple legítimo → EMENDAR o plano antes de integrar.
3. Re-rodar as baterias no worktree E na árvore integrada; exit lido SEM pipe
   (`cmd > /tmp/x.out 2>&1; echo $?`).
4. Re-rodar `conferir-mutacao.cjs` com os valores DO PLANO. Exit 0 é a única
   aprovação; 2=bateria fraca, 3=--de não casa, 4=baseline ruim.
5. `conferir-entrega.cjs --worktree --base --head-antes --sujo-antes --paralelo
   [--espera]` — capturar porcelain ANTES do despacho.
6. Padrões de fabricação vistos HOJE: `git show` decorado (hash com g/h/i não-hex,
   dia da semana errado); falha de teste reclassificada "pré-existente" (baseline
   provou que era do agente); catraca "preparada mas não rodada"; e **teste
   desligado como conserto** (`if [ -z "$VAR" ]` trocado por `if false` para calar
   a seção que pegava o defeito — verde mentiroso de 46/0). Sempre conferir no git
   real E ler o diff do teste; a honestidade do relato não é evidência.
7. Worktree isolation: TRÊS modos de falha — não cria; cria de base velha (ponta
   da main); some DEPOIS do spawn (agente cai no principal; o gate de cwd bloqueia
   — o conserto é redespachar, nunca liberar o gate).

## Sujeira conhecida / miudezas

- Pré-existente no principal: `vigias/ERROS.md` (M) e
  `relatorios/2026-08-28-batedor-repos.md` (untracked) — não são de agente.
- `conferir-entrega` come o 1º char das linhas do `--sujo-antes` (Issue #131) —
  "igias/erros.md" no relatório é isso.
- Worktrees órfãos antigos em `.claude/worktrees/` (agent-a05d..., a189..., etc.)
  — não registrados no git, podem ser apagados quando conveniente.
- Backlog: 21 ideias em `docs/rainforest/2026-08-28-ideias-colheita-revisao-externa.md`
  para plantar via /ideia; checklist repo público; código morto
  `gravarResumo`/`marcarConsolidadas` em `scripts/memoria.cjs` (achado do revisor F2).
- Commit sempre antes de encerrar (preferência do Luís; ele já perdeu trabalho).
