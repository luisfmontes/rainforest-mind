# A suíte que media a máquina do dono — lote 1 do run autônomo (2026-09-02)

Branch `fix/suite-verde`, base `135f013` (ponta da `origin/main`, PR #169).
Sessão autônoma: o Luís autorizou subagentes e foi dormir; este lote foi feito na
janela principal porque a portaria só admite agente dentro de fluxo aberto, e as
Issues aqui são consertos avulsos, fora de fluxo — como o handover do PR #169
recomendava para a #158.

> Se você só for ler um parágrafo: das 17 Issues abertas, 11 eram a mesma família —
> **bateria que mede o ambiente de quem a roda e chama isso de comportamento do
> código**. Verde na máquina do dono por coincidência (config pessoal, variável de
> ambiente, `jq`, `python3`, home sem nome curto 8.3), vermelha em qualquer outra.
> Quatro delas já estavam verdes na `main` atual (#120, #162, e duas das três da
> #163) e foram fechadas com evidência. As outras sete ganharam conserto com
> catraca de mutação. A `main` deixa de ter "4 vermelhas conhecidas" como critério
> de merge.

## O que cada Issue tinha, e o que entrou

| Issue | Causa real | Conserto | Prova |
|---|---|---|---|
| #158 | `write()`/`edit()` montavam o payload com `jq`; sem `jq`, payload vazio e gate exit 0 em tudo | os dois helpers passam a usar o `pay` em node que já existia no mesmo arquivo | bateria verde com e sem `jq` no PATH; 16 ok |
| #159 | `python3` chamado pelo nome; o instalador do Windows só cria `python` | resolvedor `$PY` (testa `python3`, depois `python`, executando cada um); sem Python 3, **PULADA exit 3** | verde com `python3`, verde só com `python`, exit 3 sem nenhum; o mesmo em `testa-statusline.sh` |
| #160 | 4 baterias liam o `config.json` real via cadeia de raiz | `RFM_ROOT` apontando para raiz descartável no topo das quatro (modelo do `testa-orcamento.sh`, #81); `testa-saude.sh` R2 idem | modo John (config com 4 gates off): antes 7 falhas, depois 0; modo CI (sem config): 0 |
| #161 | `roda_gh()` capturava `2>&1` antes do `JSON.parse` | `roda_gh_json()` lê só stdout para quem parseia; caso novo injeta ruído no stderr por `NODE_OPTIONS=--require` | ruído injetado passa; mutação (voltar a `2>&1`) fica vermelha; CI passa a rodar Node 22 **e** 24 |
| #153 | repo-alheio comparava `git-common-dir` (forma longa) com o caminho do payload (forma curta `RUNNER~1`); comparacao esperava o texto cru do `mktemp`; abertura herdava `WHATSAPP_API_BASE_URL`; saúde R2 lia config real | `realpathSync.native` nos dois lados do gate; esperado da comparacao resolvido do mesmo jeito; abertura declara a bridge numa porta que recusa na hora; R2 com `RFM_ROOT` | as quatro verdes localmente; a prova final é o CI desta PR |
| #157 | workflow desligado + máquina do Actions mais rica que a de quem instala | catraca nova `scripts/testa-dependencias-de-bateria.sh`: recusa `jq`, `rg` e `python` chamado pelo nome em bateria; `python3 -m json.tool` do `testa-heartbeat-poda.sh` virou node | 82 baterias varridas, 0 infração; 4 fixtures proibidas recusadas, o resolvedor admitido |
| #148 | `reaberto_por` aceito do `--json`; `marcar` só olhava status | `--json` com `reaberto_por` é recusado (exit 1); `estaFechado` devolve falso para bloco reaberto; `marcar` de estágio a jusante recusa com upstream reaberto (a varredura que só o `exigir` fazia) | 3 mutações, 3 vermelhas |
| #144 | `xxd`/`hexdump`/`od` lidos como telefone | isenção só para match **dentro dos grupos hex** de uma linha com forma de dump; a coluna ASCII continua recusada | 6 casos; mutação (tirar a isenção) vermelha |
| #120, #162, #163 | reportadas contra `b9a3bed` (0.79.0) | já verdes na `main` — as `FALHA` que sobram no log do `testa-contexto-sessao` são saída de mutante, impressa de propósito | exit 0 nas quatro baterias, colado nas Issues |

## O que aprendi que vale para além deste lote

**"Verde aqui" tem quatro fornecedores escondidos.** Config pessoal, variável de
ambiente, binário no PATH e forma do caminho. Nenhuma bateria declarava qual
deles usava — e a régua que sai disso é a mesma da regra 12, um degrau acima:
antes de acreditar num verde, perguntar **o que da minha máquina esta bateria
está lendo sem dizer**. A catraca de dependências fecha o terceiro fornecedor;
`RFM_ROOT` descartável fecha o primeiro; os outros dois ainda dependem de leitura.

**Um grep por linha em bash custa 15 minutos no Windows.** A primeira versão da
catraca de dependências varria 82 arquivos com um processo `grep` por linha e
"travou". Não travou: 30 mil spawns. A varredura foi para node, e é a segunda vez
em dois dias que a lição é "a ferramenta de medir tem de falar a língua do que
mede" (regra 12, item 6).

**A bateria que se acusa a si mesma.** A catraca de dependências tem fixtures com
as formas proibidas, escritas por `printf` — e a primeira rodada recusou o
próprio arquivo. Ficou fora da própria varredura, com o motivo escrito ao lado.

## Fora deste lote, e por quê

- **#142, #143, #127, #131** (guardas que medem o repositório errado; `conferir-entrega`
  cego a deleção): precisam de design — vão como fluxo próprio, lote 3.
- **#125** (backup fora da máquina) e **#145** (fechar Issue exige rodar o critério):
  o Luís pediu que a sessão decida destino e mecanismo. Vão para o mesmo lote de
  design, com as decisões marcadas como da sessão, para veto dele.
- **Fluxo 7 (recibo)**: lote 2, com `executor` em worktree, como o handover manda.

## Placar, rodado nesta máquina (Node 22, Windows 11), antes do commit

```
passada rica  (jq, python3, rg no PATH):        81 baterias — 80 verdes, 1 vermelha
passada pobre (sem jq, sem python3, sem rg):    81 baterias — 80 verdes, 1 vermelha
  (interprete: python)      ← testa-medir-injecao e testa-statusline resolveram o python.exe
vermelha nas duas: scripts/testa-triagem.sh — pré-existente, afirma 219 funções de um
  .prw fora do repo que hoje tem 223. Issue #170, mesma família, fora deste PR.
```

## O que o gate de commit ensinou no fim

O gate de publicação passou a conferir o **commit inteiro** (Issue #165, PR #167), e
este foi o primeiro PR a editar arquivos antigos que já carregavam forma de dado
sensível em comentário: a chave `API_KEY` seguida de dois-pontos numa explicação do próprio detector, dois
caminhos de home em comentários de bateria, um e-mail de fixture, a palavra `token` seguida de dois-pontos e um número.
Nenhum era dado de ninguém; todos barraram o commit. Cinco reescritas e um
marcador `rainforest-gate: dados-de-exemplo` (no `baterias.yml`, com o motivo ao
lado) depois, o gate saiu 0. Fica a observação: **o gate confere o arquivo, não o
diff** — quem editar um arquivo antigo paga pelo conteúdo dos outros. É desenho
(o incidente que o motivou era conteúdo antigo entrando por script), mas vale
saber antes de tocar em bateria com fixture.
