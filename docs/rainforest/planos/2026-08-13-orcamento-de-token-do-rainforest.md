# Plano: Orçamento de token do rainforest

Design: docs/rainforest/design/2026-08-13-orcamento-de-token-do-rainforest.md

## O que não pode quebrar

- A suíte inteira do `CONTRIBUTING.md:11` continua verde: `for t in scripts/testa-*.sh hooks/testa-*.sh; do bash "$t"; done`.
- O hook de abertura continua emitindo o mesmo payload — nada aqui edita `hooks/foco-session-start.cjs` nem `hooks/lib/contexto-sessao.cjs`. Os 98,6% são achado, não tarefa (Fora de escopo do design).
- Os modos que o `scripts/medir-injecao.py` já tem (padrão, `--ultimas`, `--entrega`) continuam funcionando com a mesma saída.
- Nenhum artefato daqui lê rede, nem exige chave de API. O `count_tokens` está Fora de escopo.
- Byte é a medida primária em toda saída; token só aparece como coluna secundária e sempre acompanhado do fator (D5).

## Derivação registrada (não é decisão nova)

O design fixou dois artefatos (D8) mas nomeou só um dos lados como arquivo:
`testa-orcamento.sh`. No repo, todo `testa-X.sh` testa um `X` que existe em
`scripts/` — o teste não é o mecanismo, é quem prova o mecanismo. Então o lado
determinístico vira **dois** arquivos: `scripts/orcamento.cjs` (mede e sai com
exit ≠ 0) e `scripts/testa-orcamento.sh` (prova o `orcamento.cjs` e o roda
contra o repo real, que é a asserção que gateia de verdade). Isso não contraria
o "script novo foi descartado" do D2: aquele descarte era sobre duplicar leitura
de **transcript**, e o `orcamento.cjs` não lê transcript nenhum.

## Tarefas

### 1. Fixar o fator byte→token com proveniência declarada [tipo: pesquisar]
depende de: nenhuma
paralela: sim
pronto quando: existe `docs/rainforest/design/2026-08-13-orcamento-de-token-do-rainforest.md` com a seção `## Em aberto` reescrita para conter o valor numérico escolhido e a frase de proveniência, e `grep -c 'BYTES_POR_TOKEN' docs/rainforest/design/2026-08-13-orcamento-de-token-do-rainforest.md` devolve `1` ou mais.

Restrição: o fator tem que sair de evidência **offline** — contagem sobre texto real do próprio repo contra algum tokenizador já instalado na máquina, ou, não havendo nenhum, uma constante declarada com a fonte nomeada e a palavra "proxy" ao lado. Nunca um número sem origem escrita. Se nenhum tokenizador local existir, isso se **relata**, não se contorna instalando nada (regra 15).

### 2. `scripts/orcamento.cjs` — mede as fontes do repo e acusa estouro [tipo: implementar]
depende de: nenhuma
paralela: sim
pronto quando: `node scripts/orcamento.cjs` imprime uma linha para cada uma das três fontes (saída do hook, descriptions das skills próprias, descriptions dos agentes próprios), mais uma linha de total, e sai com exit `0`; e `node scripts/orcamento.cjs --teto 1000` sai com exit `1` imprimindo o estouro.

O que ele mede, em byte:
- saída do hook: executa `hooks/foco-session-start.cjs` e conta o campo `additionalContext`, não o JSON inteiro;
- descriptions das skills de `skills/*/SKILL.md` e dos comandos de `commands/*.md` que aparecem na listagem;
- descriptions dos agentes de `agents/*.md`.

Tetos: `8000` para o hook sozinho (o `ORCAMENTO_BYTES` que já existe em `hooks/lib/contexto-sessao.cjs:50`, lido de lá e nunca redigitado) e `14000` para o agregado (D7). O flag `--teto <n>` sobrescreve o agregado, e existe para o teste poder provar o caminho vermelho.

### 3. `scripts/medir-injecao.py --repartir` — reparte a abertura pelo transcript [tipo: implementar]
depende de: 1
paralela: nao
pronto quando: `python scripts/medir-injecao.py --repartir` sai com exit `0` e a saída contém, cada uma em sua linha com o byte medido: `skill_listing`, `deferred_tools_delta`, `agent_listing_delta`, um subtotal identificado como `rainforest-mind`, e uma linha `nao atribuido`.

Detalhes que o design já fixou:
- a fatia própria sai por prefixo `rainforest-mind:` dentro de `skill_listing.names` e do `agent_listing_delta` (D4);
- byte é primária, token estimado é coluna secundária e o fator da tarefa 1 aparece impresso na saída (D5);
- a linha `nao atribuido` é o total da abertura em token (que o modo `--ultimas` já sabe ler) menos o que foi atribuído, convertido pelo fator — e vem rotulada como estimativa.

### 4. `scripts/testa-orcamento.sh` — prova o `orcamento.cjs` nos dois caminhos [tipo: teste]
depende de: 2
paralela: nao
pronto quando: `bash scripts/testa-orcamento.sh` sai com exit `0`; e, com o `orcamento.cjs` sabotado para ignorar o teto, o mesmo comando sai com exit ≠ `0`.

O teste tem que provar as duas pernas — que passa no verde e **falha no vermelho**. Teste que só afirma o caminho feliz não prova o gate. Uma das asserções roda o `orcamento.cjs` contra o repo real sem `--teto`, e é ela que faz a suíte do `CONTRIBUTING.md:11` acusar quando o plugin engordar além dos 14.000 B.

### 5. README, CONTRIBUTING e versão [tipo: docs]
depende de: 2, 3, 4
paralela: nao
pronto quando: `grep -c 'orcamento' README.md` devolve `1` ou mais, `grep -c 'repartir' README.md` devolve `1` ou mais, e `grep '"version"' .claude-plugin/plugin.json` mostra `0.65.0`.

A versão pula o `0.64.0` de propósito: aquele número já está tomado pela branch `esteira-decisao-que-evapora`, cujo PR #9 está **aberto e não mesclado** — conferido em 2026-08-13 por `gh pr view 9`. Reusar o mesmo número criaria duas versões diferentes com o mesmo nome dependendo de qual PR mesclasse primeiro.
