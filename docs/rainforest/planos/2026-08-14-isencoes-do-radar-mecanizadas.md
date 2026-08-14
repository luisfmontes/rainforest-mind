# Plano: Isenções do radar mecanizadas

Design: docs/rainforest/design/2026-08-14-isencoes-do-radar-mecanizadas.md

## O que não pode quebrar

- A suíte inteira do `CONTRIBUTING.md:11` continua verde, com a exceção já conhecida e plantada do `testa-saude.sh`.
- `node scripts/orcamento.cjs` continua saindo `0`: o hook abaixo de 8.000 B e o agregado abaixo de 14.000 B. **Esta é a restrição mais apertada da entrega** — a folga do hook era de 202 B quando o design fechou.
- Os blocos que a injeção já emite (regras, foco, sessões paralelas, dependências de ambiente) continuam saindo com o mesmo conteúdo quando nenhuma isenção dispara. Quem não configurou nada não vê diferença nenhuma.
- Nada aqui lê rede, nem escreve fora do repositório — com a única exceção da tarefa 6, que é do usuário e roda na janela principal.
- `hooks/testa-contexto-sessao.sh` (123 asserções) continua verde.

## Por que quase tudo é serial

Cinco das seis tarefas tocam `hooks/lib/contexto-sessao.cjs`. Despachar em
paralelo agentes que editam o mesmo arquivo produz conflito de merge, e o
isolamento por worktree não resolve isso — ele evita que se atropelem no disco,
não que divirjam no conteúdo. A serialização aqui é contenção de arquivo, não
falta de análise: as dependências declaradas abaixo são reais em cada caso.

## Tarefas

### 1. Duas funções puras: pastas do foco e expediente [tipo: implementar]
depende de: nenhuma
paralela: sim
pronto quando: os dois comandos abaixo imprimem exatamente o esperado.

```
node -e "const m=require('./hooks/lib/contexto-sessao.cjs');console.log(JSON.stringify(m.pastasDoFoco('## Ativo\nPastas: C:/a, C:/b\n')))"
```
devolve `["C:/a","C:/b"]`.

```
node -e "const m=require('./hooks/lib/contexto-sessao.cjs');const c={expediente:{dias:[1,2,3,4,5],de:'08:00',ate:'18:00'}};console.log(m.dentroDoExpediente(new Date('2026-08-15T14:00:00'),c),m.dentroDoExpediente(new Date('2026-08-16T14:00:00'),c))"
```
devolve `true false` (15/08/2026 é sábado, 16/08 é domingo — confira as datas antes de fixar a asserção; o que importa é um dia útil dentro da faixa e um fim de semana).

Ambas exportadas em `module.exports`. `pastasDoFoco` aceita lista separada por vírgula e devolve `[]` quando o campo não existe. `dentroDoExpediente` devolve `null` — não `false` — quando não há `expediente` no config: "não sei" é diferente de "não é expediente", e o D6 depende dessa distinção para anunciar a ausência.

### 2. `focoAtivoEmOutraJanela` [tipo: implementar]
depende de: 1
paralela: nao
pronto quando:

```
node -e "const m=require('./hooks/lib/contexto-sessao.cjs');const ag=Date.now();console.log(m.focoAtivoEmOutraJanela([{cwd:'C:/a',prompt_ts:ag-60000,stop_ts:0}],['C:/a'],15,ag),m.focoAtivoEmOutraJanela([{cwd:'C:/a',prompt_ts:ag-3600000,stop_ts:0}],['C:/a'],15,ag),m.focoAtivoEmOutraJanela([{cwd:'C:/z',prompt_ts:ag-60000,stop_ts:0}],['C:/a'],15,ag))"
```
devolve `true false false` — janela na pasta do foco com sinal de 1 min isenta; a mesma com sinal de 1 hora não isenta (passou da ociosidade de 15 min, D7); janela em outra pasta não isenta.

A comparação de caminho normaliza separador e caixa, porque o `cwd` do `sessoes.json` vem com barra e caixa variáveis no Windows. **Não** deve casar por sufixo ou por `includes`: `C:/a` não pode casar `C:/abc`.

### 3. O veredito componível, e o anúncio quando falta dado [tipo: implementar]
depende de: 1, 2
paralela: nao
pronto quando: `node hooks/foco-session-start.cjs | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const c=JSON.parse(s).hookSpecificOutput.additionalContext;console.log(/nao cobrar desvio|não cobrar desvio/i.test(c)?'VEREDITO':'sem veredito')})"` imprime `sem veredito` no estado atual da máquina (nenhuma janela na pasta do foco, expediente não configurado) **e** `node scripts/orcamento.cjs` sai `0`.

Uma linha só, carregando os motivos aplicáveis (D10). Quando faltar dado para julgar — sem `Pastas:` no foco, sem `expediente` no config — não isenta (D6, falha fechada) e anuncia a ausência em uma linha, nomeando o que falta e o efeito prático, no espírito da regra 14. Veredito e anúncio são mutuamente exclusivos: não há como julgar sem dado.

### 4. Bateria com mutação [tipo: teste]
depende de: 3
paralela: nao
pronto quando: `bash hooks/testa-contexto-sessao.sh` sai `0` com as asserções novas somadas às 123 existentes; e, para **cada** uma das três funções novas, existe saída colada mostrando que sabotar a função em uma **cópia** derruba a asserção correspondente.

Cobrir, no mínimo: pasta do foco ausente (não isenta e anuncia); janela do foco fria além da ociosidade (não isenta); janela em pasta parecida mas diferente (`C:/abc` contra `C:/a`, não isenta); expediente ausente (não isenta e anuncia); dentro e fora da faixa horária; e o veredito compondo os dois motivos numa linha só.

### 5. Template do foco, README e versão [tipo: docs]
depende de: 3
paralela: nao
pronto quando: `grep -c 'Pastas:' scripts/setup.cjs` devolve `1` ou mais; `grep -c 'expediente' README.md` devolve `1` ou mais; e `bash scripts/testa-versao.sh` sai `0`.

O `FOCO_MODELO` do `setup.cjs` passa a trazer o campo `Pastas:` com explicação de uma linha. O README documenta o campo, o `expediente` do `config.json`, e **o que acontece quando não estão configurados** — que é o caso de todo mundo hoje. A versão sobe, e o `testa-versao.sh` (que entrou no PR #11) é quem prova que subiu nos dois lugares.

### 6. Configurar os dados do usuário [tipo: configurar]
depende de: 3, 5
paralela: nao
pronto quando: `node hooks/foco-session-start.cjs` passa a emitir o veredito quando há sessão viva na pasta do foco, provado com a saída colada; e `node scripts/orcamento.cjs` continua saindo `0` **com o veredito presente**, que é o pior caso de orçamento.

**Esta tarefa roda na janela principal, nunca em agente:** ela edita `~/.rainforest/FOCO.md` e `~/.rainforest/config.json`, que são dados do usuário fora do repositório — a regra 15 proíbe agente de tocar neles. E ela **exige a palavra do usuário sobre os valores**: quais pastas contam como o foco atual, e qual é a faixa de expediente dele. Nenhum dos dois se descobre olhando o ambiente.
