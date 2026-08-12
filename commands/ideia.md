---
description: Avalia se a ideia está no escopo e a planta se estiver fora
argument-hint: [ideia em uma frase — vazio para listar plantadas]
---

A fonte da verdade das ideias é `C:\Projetos\rainforest-mind\ideias.jsonl` —
um objeto JSON por linha, com os campos: `id` (kebab-case), `titulo`,
`descricao`, `contexto` (de onde surgiu e por quê), `projeto` (repo/pasta,
ou "solta"), `ao_colher` (primeiro passo, ou null), `status`
("plantada"/"em-colheita"/"colhida"/"unificada"), `plantada_em`, e para
colhidas `colhida_em` +
`resultado`. Campo opcional `tipo`: ausente ou `"ideia"` (padrão) para ideia
do usuário; `"observacao"` para as da regra 13 — geradas por correção dele
sobre método, com `ao_colher` = mudança de regra. `/ideia` sem argumento
lista só as ideias; observação é assunto do jardineiro de sexta.

Se `$ARGUMENTS` estiver vazio: leia o jsonl e liste as **plantadas** em
markdown legível (título, há quantos dias plantada, projeto, contexto em uma
linha), mais novas primeiro; feche com uma linha resumindo as colhidas.

Se `$ARGUMENTS` tiver texto: avalie se a ideia está dentro do foco declarado
(FOCO.md do repo rainforest-mind).

- **Se estiver no escopo:** confirmar e perguntar: "Isso está no foco — entra
  na tarefa atual ou planto para depois?"
- **Se estiver fora:** plantar. Se o `projeto` não estiver óbvio pelo contexto
  da conversa, perguntar em uma linha antes de gravar. Confirmar: "plantada,
  de volta a [tarefa]".

Colher não apaga a linha: reescreve com `resultado`. Colhida ≠ apagada.

**A escrita é do script, nunca sua.** `scripts/ideias.cjs` faz trava entre
sessões paralelas, releitura do arquivo vivo, backup, gravação atômica,
carimbo de data pelo relógio local e conferência byte a byte das linhas que
não eram alvo — e reverte tudo saindo com exit ≠ 0 se qualquer prova falhar.
**Não edite o `ideias.jsonl` à mão nem com script improvisado.** Os quatro
cuidados que moravam aqui em prosa viraram código em 2026-08-08, depois de
dois appends quebrados no mesmo dia, uma data gravada no futuro e um `unificar`
que precisou inventar status no meio do caminho.

```
node scripts/ideias.cjs plantar  < nova.json                    # JSON por stdin
node scripts/ideias.cjs colher   --id <id> < resultado.json     # {"resultado": "..."}
node scripts/ideias.cjs editar   --id <id> < mudancas.json      # só o que ainda está aberto
node scripts/ideias.cjs iniciar  --id <id>                      # plantada → em-colheita
node scripts/ideias.cjs unificar --manter <id> --absorver <id> < fundida.json
node scripts/ideias.cjs reparar  [--id <id> | --todas] [--conferir]
node scripts/ideias.cjs listar   [--status plantada] [--tipo ideia|observacao|todos]
node scripts/ideias.cjs conferir                                # saúde do arquivo
```

Node porque o plugin é instalado por outra gente: os hooks já exigem Node, e o
Claude Code não garante Python (a lista oficial de dependências extras tem
`ripgrep` e mais nada). O `scripts/ideias.py` continua no repo como gêmeo — a
mesma bateria roda contra os dois (`IDEIAS="python scripts/ideias.py" bash
scripts/testa-ideias.sh`), e é assim que se prova que o port não perdeu nada.
Escrita nova vai pelo `.cjs`.

`reparar` é para a linha que **entrou no arquivo sem passar pelo script** — o
`conferir` acusa "status desconhecido" ou campo de estado vazio, e o `editar`
não resolve porque `status` e `plantada_em` são proibidos na entrada (é essa
proibição que impede o modelo de digitar data). Ele só preenche o que está
**ausente**: valor errado porém existente é assunto do `editar`, que deixa
rastro de decisão. O `status` sai inferido do próprio registro e a
`plantada_em` sai da **data do commit que introduziu a linha** — se o git não
souber, ele recusa em vez de carimbar hoje numa linha que não nasceu hoje, e
aí a data vai à mão em `--plantada-em AAAA-MM-DD`. Rode com `--conferir`
antes: descreve tudo que faria, sem gravar.

Dois cuidados continuam seus, porque o script não alcança:

- **Escreva o JSON com a ferramenta de escrita de arquivo, nunca por heredoc
  do shell** — o shell come as barras do caminho do Windows. Em 2026-08-08
  isso quebrou uma gravação e o script recusou, em vez de gravar corrompido.
- **Não passe data nenhuma.** `plantada_em`, `colhida_em` e afins vindos da
  entrada são erro, não aviso: quem carimba é o script, do relógio local.

Com `$ARGUMENTS` vazio, `listar` já entrega as plantadas com a idade contada —
formate legível a partir da saída dele, sem recontar nada por conta própria.
