# Provas das tarefas 1 e 2 do fluxo 2026-11-07-leitores-cegos

As duas saídas estão coladas abaixo, sem edição. Os dois agentes são `general-purpose`, com `model: sonnet`, despachados com o briefing das referências novas. O briefing da tarefa 1 chegou ao agente com um bloco `## Memória do assunto` (três resumos de outras sessões) que o hook `memoria-assunto-agente.cjs` anexou sozinho. A revisão 3 achou isso no transcrito, e por isso existe o D11 (`Contexto: cego`). O briefing da tarefa 2 não recebeu o bloco.

O plano (`docs/rainforest/planos/2026-11-07-leitores-cegos.md`) traz só o resumo, e é aqui que está a evidência.

## Tarefa 2: diagnóstico cego do #648, na base 32be77c2 (2.5.0)

**Montagem.**
- Worktree descartável em `32be77c2`.
- Fixture `Painel.tsx` com `const Painel: React.FC = () => {...}` e `function Simples()`.
- Repro: `node scripts/catalogo-funcoes.cjs complexas --raiz <pasta da fixture>`, que devolveu:

```
0 cognitiva  1 ciclomática  Painel.tsx:L6 Simples
medida aproximada (leitura de texto, sem parser): confira no código antes de concluir
```

**Saída do agente.**

```
Causas candidatas, da mais para a menos provável:

**1. O cadastro de definições nunca reconhece `Painel`: a regra de função de topo exige `=` logo depois do nome, e a anotação de tipo `: React.FC` quebra isso. (mais provável)**
- Evidência:
  - `hooks/lib/definicoes.cjs:33` é `/^(?:export\s+)?(?:const|let|var)\s+([\w$]+)\s*=\s*(?:async\b|\()/`. Depois do nome só admite `\s*=`. Na linha 2 do fixture, `const Painel: React.FC = () => {`, vem `:` logo depois de `Painel`, então a regra não casa.
  - A única outra regra de `topo` que poderia pegar a linha é `export default function`, e a linha não é isso.
  - O conjunto `metodo` (linha 53) exige recuo (`^\s+`). `Painel` está na coluna zero, então também não casa.
  - `definicoesDoArquivo` (`scripts/catalogo-funcoes.cjs:160-174`) só usa `casar` por linha. Sem match, `Painel` nunca entra em `defs`.
  - `medirArquivo` (`scripts/lib/complexidade.cjs:352`) só mede o que veio em `defs`. O `Painel` some sem entrar em `naoMedidas`, por isso a saída não avisa de nada.
  - `Simples` casa pela regra da linha 32 (`function Simples`), o que bate com a saída observada.
- Checagem: rodar `node -e "const {casar}=require('./hooks/lib/definicoes.cjs');for(const l of ['const Painel: React.FC = () => {','const Painel = () => {'])console.log(JSON.stringify(l),casar(l,'js','topo'))"` dentro do worktree.
  - Se a causa for esta, a primeira linha devolve `null` e a segunda devolve `"Painel"`.
  - Se as duas devolverem `"Painel"`, a causa está derrubada e o defeito é posterior (causa 2).

**2. Menos provável: `Painel` entra em `defs`, mas a medição o descarta ou o aninha.**
- Evidência:
  - `complexidade.cjs:362` localiza a ficha com `f.l === def.linha && f.t === def.nome`.
  - O corpo vem de `acharCorpo` (`:248`), que lida com `<...>` de genérico e com tipo literal antes da seta. A anotação `React.FC` e o JSX (`<div>a</div>`, que o tokenizador trata como `<`/`>`) podem confundir a busca da seta ou do fechamento das chaves.
  - `:369-374` descarta com `corpo passou por ...` ou `corpo não fechou`, mas esses casos iriam para `naoMedidas`. A saída real só tem a linha de aviso genérico, então esta causa só vale se `naoMedidas` for impresso e estiver vazio. É a hipótese mais fraca porque o sintoma não mostra nenhum aviso.
- Checagem: depois de aplicar a checagem 1, rodar `node -e "const c=require('./scripts/lib/complexidade.cjs');const t=require('fs').readFileSync('C:/Users/Luis/AppData/Local/Temp/diag648/Painel.tsx','utf8');console.log(JSON.stringify(c.medirArquivo(t,'js',[{linha:2,nome:'Painel'},{linha:6,nome:'Simples'}]),null,1))"`.
  - `Painel` em `medidas` com cognitiva maior que 0: a medição está sã e o defeito é só a causa 1.
  - `Painel` em `naoMedidas`, ou ausente das duas listas: a causa 2 está confirmada.

**3. Mais fraca: filtro de candidatos ou de ordenação/`top` descartando o resultado.**
- Evidência: `candidatos()` (`catalogo-funcoes.cjs:143-147`) filtra por extensão, geração e teste. `.tsx` está em `EXTENSOES` (`definicoes.cjs:20`) e `Simples` do mesmo arquivo aparece, então o arquivo não é filtrado. O `top` padrão é 10 e há só uma função na saída, então o corte também não explica. Está aqui só por completude.
- Checagem: rodar o repro com `--top 100`. Se `Painel` continuar ausente, a causa 3 cai. Se aparecer, o corte era o problema.

diagnóstico completo
```

As três candidatas trazem `arquivo:linha` e uma checagem, e nenhuma propõe conserto, como o critério da tarefa pede.

**Checagem discriminante, rodada pela janela principal na base:**

```
$ node -e "const {casar}=require('./hooks/lib/definicoes.cjs');for(const l of ['const Painel: React.FC = () => {','const Painel = () => {'])console.log(JSON.stringify(l),casar(l,'js','topo'))"
"const Painel: React.FC = () => {" null
"const Painel = () => {" Painel
```

**Conserto real.** `git show 3e344d23 -- hooks/lib/definicoes.cjs` mostra que o #651 trocou
justamente essa regex. Ela passou a aceitar a anotação de tipo antes do `=`, e também `function`,
`memo(` e `forwardRef(`. A candidata nº 1 é a causa real.

## Tarefa 1: leitor cego sobre o plano deste fluxo

**Saída do agente:**

```
Achei 4 bloqueantes, 5 maiores e 3 menores. A causa comum é que as tarefas dizem o que verificar, mas não o que escrever.

Não rodei nenhum dos critérios de pronto. Conferi só que os arquivos, scripts e o commit `32be77c2` (2.5.0) existem. O worktree já traz os arquivos que as tarefas 1 e 2 mandam criar, mas li o plano como se estivessem ausentes.

## Bloqueantes

**Tarefa 1**
- Achado: o plano manda criar `skills/plano/references/leitor-cego.md` e não diz o que vai nele. As quatro categorias de busca (decisão em aberto, passo vago, contradição do design, critério não rodável), o formato dos achados e a regra "só ler, não editar" estão só no design (D3, D4). O design não está em `arquivos:`, e o haiku recebe só o texto da tarefa.
- Orientação: o plano precisa incluir o briefing literal do leitor, ou listar o design em `arquivos:` e dizer "seções D2 a D4 viram o briefing, com estes três placeholders: ...". Também precisa dizer a estrutura do arquivo (por que existe, quando, despacho, briefing).

**Tarefa 1 (critério de pronto)**
- Achado: o critério pede despachar um `general-purpose` sonnet com o briefing e colar a saída. O executor é o `rainforest-mind:executor`, e todos os agentes do plugin têm "All tools except Agent". Ele não consegue despachar. Também não está dito quem preenche `<worktree>` em `git -C <worktree> status --short`.
- Orientação: o plano precisa dizer quem roda o despacho. A sessão principal, depois da tarefa, é o caminho que funciona. Ou então trocar o critério por algo que o haiku rode: um `grep` que confira as seções e os três graus no arquivo.

**Tarefa 1 (critério de pronto)**
- Achado: "`git status --short` vazio depois do despacho" não vale no momento da tarefa. As edições do próprio executor ainda estão sem commit, e `docs/rainforest/estado/...json` já está modificado (`M` no gitStatus).
- Orientação: o critério precisa comparar com o estado antes do despacho (por exemplo `git diff --stat` antes e depois), ou exigir commit antes do despacho.

**Tarefa 2**
- Achado: vale o mesmo para a referência. `diagnostico-cego.md` não tem conteúdo especificado: de 1 a 3 causas candidatas, `arquivo:linha`, evidência, checagem que prova ou derruba, "não pede conserto" (D5), a tabela candidata / checagem / resultado / veredito e a regra de inconclusivo (D6). Tudo isso está só no design.
- Orientação: o plano precisa trazer o prompt literal e o procedimento, ou apontar o design como fonte com as seções que viram texto.
- Achado: o critério também depende de despachar um agente (o executor não tem Agent) e de criar "um worktree descartável no commit 32be77c2", sem dizer o comando. O comando é `git worktree add <caminho fora do repo> 32be77c2`, com limpeza no fim.

## Maiores

**Tarefa 1**
- Achado: o plano não diz onde nem com que texto editar `skills/plano/SKILL.md`. O `## Fechar` só aparece em "diz quando rodar (D1)... aponta... manda corrigir". Faltam três coisas:
  - A lista de tipos (D1 diz implementar, configurar e teste; o template do plano também admite "sem tipo").
  - O destino do achado `[design]` (D4).
  - O orçamento de bytes. O design diz que o SKILL.md tinha 15.365 bytes antes da tarefa, e o teto é 16.384, então sobram cerca de 1.000 bytes.
- Orientação: dar o texto exato do bloco, ou um limite como "no máximo 800 bytes". Dizer onde ele entra, antes do bloco `estado.cjs marcar`.

**Tarefa 2**
- Achado: o plano não diz onde, nem com que redação, entram o passo novo na Fase 3 de `skills/depurar/SKILL.md` e o aviso em `agents/depurador.md`.
- Achado: a segunda metade de D7 não é realizada por nenhuma tarefa de forma explícita. É a frase "a janela principal despacha o `depurador` e o diagnóstico cego juntos e compara os dois relatos". O plano só cita o "pule e avise no relato" em `depurador.md`. Não diz em qual arquivo vai a instrução para quem despacha, e `depurador.md` tem um bloco `ponte-codex` longo no topo.
- Orientação: dizer em que arquivo e seção entra a regra da janela principal. Dizer também onde fica o aviso do subagente, depois do bloco `ponte-codex` e sem tocar no `perfil-de-trabalho`.

**Tarefa 2 (critério de pronto)**
- Achado: o critério depende de a saída de um modelo citar `scripts/lib/complexidade.cjs` como candidata nº 1. É não determinístico e pode falhar mesmo com o prompt correto. Também não está dito se o repro roda com `catalogo-funcoes.cjs complexas --raiz <dir>`, e esse script exige `--raiz` ou usa o diretório atual.
- Orientação: aceitar "entre as candidatas" em vez de "nº 1", ou dizer como tratar uma falha. Dar o comando do repro completo, com a fixture `.tsx` a criar no worktree descartável.

**Tarefa 3**
- Achado: o `README.md` está em `arquivos:`, mas não contém "2.5.1" nem nenhuma menção de versão (grep sem resultado). O plano não diz o que mudar nele. A memória "README acompanha toda entrega" não responde a isso.
- Orientação: nomear a seção do README a editar e o texto (um parágrafo sobre cada passo novo, por exemplo). Ou retirar o README de `arquivos:`.

## Menores

- **Tarefa 3:** "`conferir-versao.cjs` aceita a 2.6.0" não diz o exit esperado. O script compara com `origin/main` (e faz fetch, salvo `--sem-fetch`), recusa se a versão local não for maior, e tem um exit `4` próprio. Orientação: "exit 0, com `--sem-fetch` se não houver rede".
- **Tarefa 3:** a entrada do CHANGELOG não tem formato dito. O padrão é `## 2.6.0 — 2026-11-07` acima da 2.5.1, com bullets em negrito. Orientação: citar a 2.5.1 como modelo.
- **Tarefa 3:** `.claude-plugin/marketplace.json` não tem campo `version`, então o escopo está certo.

Em "O que não pode quebrar", `bash scripts/testa-teto-skills.sh` e o `disallowedTools: Agent` existem e conferem. A linha "intacto" do bloco `perfil-de-trabalho` não traz comando de conferência.

leitura completa
```

**Leitura da janela principal sobre essa saída:**
- O formato pedido saiu inteiro: três graus, tarefa afetada, trecho citado e orientação, sem código proposto.
- **`git status --short` depois da volta:** não saiu vazio. No worktree do fluxo apareceu ` M docs/rainforest/planos/2026-11-07-leitores-cegos.md`, que era a correção do critério da T2, feita pela janela principal enquanto o leitor rodava. O worktree da base saiu vazio. Nenhuma alteração era do leitor.
- **"README sem 2.5.1":** foi leitura concorrente com o commit de versão `c10c7ebd`, feito às 13:15, enquanto o leitor rodava. Isso virou a linha "commite o plano antes do despacho" na referência.
- **Destino dos achados:** não foram aplicados ao plano. As tarefas foram escritas pela janela principal, conforme a memória "manifesto sem agente sonnet de escrita". E o plano é só de docs, caso em que o D1 dispensa o leitor.
