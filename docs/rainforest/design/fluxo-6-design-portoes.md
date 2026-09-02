# Fluxo 6 — Design: `portoes.cjs` (oráculos executáveis)

> Status: design · Depende de: fluxo 1 fechado (estado.cjs endurecido) · Origem: reescrita de Leonxlnx/unlazy (MIT), sob as regras do rainforest
> Atribuição obrigatória no cabeçalho do script e no manual: "reescrito a partir de unlazy (MIT), Leonxlnx".

## Problema

O fluxo 1 endureceu o ciclo `executar`/`verificar`: `ok` exige evidência colada, `reprovado` reabre o estágio a montante, tentativas têm teto de 3. Mas a evidência ainda é **prosa colada** — o modelo cola um output e afirma que ele prova o critério. Nada re-executa. Nada impede que o critério seja "tudo funciona" com evidência `echo ok`.

O unlazy resolve isso com um oráculo executável: cada portão declara o comando que o decide e o marcador de sucesso que o output deve conter. Cumprido = **exit 0 E match do marcador**, os dois, re-executáveis a qualquer momento. A autoria do portão vira o único elo fraco — e um lint pega isso na origem.

## O que entra (e o que fica de fora)

**Entra:**
- Arquivo de portões por fluxo, formato estrito, parseável por regex simples.
- `portoes.cjs` com quatro modos: `status` (nunca executa), `lint` (nunca executa), `rodar`, `rodar --reverificar`.
- `ABANDONA:` — desistência terminal com razão obrigatória, que nunca é sucesso.
- Guarda de progresso no hook de Stop.

**Fica de fora (decisão, não esquecimento):**
- Modelo de aprovação de comandos herdados (`~/.unlazy/approved`, binding de shell/CWD/PATH). Faz sentido para ledgers de terceiros; o rainforest é solo e os portões nascem no `plano` da própria sessão. Se um dia entrar território multi-repo, revisitar.
- `OWNS:`, waves, dispatch paralelo. O pipeline é sequencial por desenho.
- `--jobs`. Execução sequencial, sempre, na ordem do arquivo.

## Formato do arquivo

Um por fluxo: `docs/rainforest/fluxos/<id>/portoes.md` (ajustar ao layout real — pergunta P1 abaixo).

```markdown
# Portões: <nome do fluxo>

- [ ] P1: <resultado observável, medido do artefato>
  CHECK: node scripts/verifica-x.cjs
  ESPERA: verificacao passou
  EVIDENCIA: pendente

- [ ] P2: <resultado que nenhum comando decide>
  EVIDENCIA: pendente
```

Regras estritas, iguais ao original:
- Id único e explícito por portão.
- Portão executável tem `CHECK:` e `ESPERA:`; portão manual não tem nenhum dos dois. Meio-termo é erro de parse.
- `ESPERA:` é um marcador que só aparece quando **todas** as asserções do script passaram — nunca uma substring que um erro parcial também imprime.
- Cumprido = exit 0 do processo E match do `ESPERA:` no output combinado (stdout+stderr).
- Checkbox marcado com `EVIDENCIA: pendente` conta como **não cumprido**. O arquivo não é a verdade; a execução é.
- Portão impossível não se apaga em silêncio:

```markdown
ABANDONA: P2 <razão não-vazia e o que precisa de decisão humana>
```

Abandono é terminal mas nunca é conclusão: `rodar` sai com 1 e imprime `DEVOLUCAO OBRIGATORIA`. Arquivo malformado, sem portões, id duplicado ou razão vazia é erro (exit 2), não conclusão.

## Comandos

```
node scripts/portoes.cjs status <arquivo>        # parse + estado, NUNCA executa. exit 0/2
node scripts/portoes.cjs lint <arquivo>          # qualidade dos oráculos, NUNCA executa. exit 0/1/2
node scripts/portoes.cjs rodar <arquivo>         # executa CHECKs pendentes em ordem. exit 0/1/2
node scripts/portoes.cjs rodar --reverificar <a> # re-executa TODOS, inclusive já cumpridos
```

`rodar` grava em cada portão cumprido a evidência resolvida: shell usado, CWD, exit, resultado do match e fingerprint (sha256 truncado) do output — output bruto de sucesso não persiste. Escrita atômica (temp + rename), como o resto do estado.

### O lint (a peça mais valiosa)

O checker prova que o oráculo declarado rodou e retornou o prometido. Ele não pergunta se o oráculo **vale alguma coisa**. `CHECK: echo ok` / `ESPERA: ok` passa em tudo. O lint audita a autoria, sem executar nada:

- **Erro:** comando de saída fixa (`echo`, `printf`, `true`, `exit 0` sozinhos); `ESPERA:` vazio ou trivial (`ok`, `done`, `0`); título que nomeia atividade ("rodar os testes") em vez de resultado ("testes do módulo X passam").
- **Aviso:** `ESPERA:` que é substring provável de mensagem de erro; número copiado do enunciado direto pro `ESPERA:` (número medido deve vir do script, não do prompt); dependência de `grep`/`tail`/`tr` (não existem no Windows puro — usar script Node).

`--strict` promove avisos a falha. E o lint pode ser portão de si mesmo:

```markdown
- [ ] P0: os portões deste fluxo têm oráculos honestos
  CHECK: node scripts/portoes.cjs lint docs/rainforest/fluxos/6/portoes.md
  ESPERA: LINT OK
```

## Encaixe no pipeline (mecânica, não instrução)

Dois ganchos no `estado.cjs`, ambos por exit code:

1. **`plano` só fecha com lint limpo.** Se `portoes.md` existe para o fluxo, o gate de fechamento do `plano` roda `portoes.cjs lint` e exige exit 0. Portão ruim é defeito de planejamento — pega na origem, não na entrega.
2. **`ok` do `verificar` exige `rodar` limpo.** Quando há portões, a evidência colada deixa de ser suficiente: o gate roda `portoes.cjs rodar` e o `ok` só grava com exit 0. `reprovado` continua reabrindo a montante como no fluxo 1; o teto de 3 tentativas passa a ter uma saída definida — na terceira falha, o `proximo` instrui `ABANDONA:` + devolução, em vez de tentativa 4.

Fluxo sem `portoes.md` segue funcionando como hoje (evidência colada). Portões são opt-in por fluxo — regra do território pode torná-los obrigatórios depois.

## Guarda de progresso no hook de Stop

Se o hook de Stop passar a bloquear com portão aberto, copiar a guarda do unlazy: o bloqueio se libera sozinho após **6 bloqueios consecutivos sem mudança semântica** do estado — onde "semântica" é o hash do conjunto {estado de cada portão, estágio ativo, contador de tentativas}. Editar texto do arquivo não é progresso; mudar o estado de um portão é. Isso elimina o risco clássico de hook de Stop: a sessão presa num loop de bloqueio sem caminho de saída.

Estado da guarda por sessão em `.rainforest/hook-estado.json`, com o mesmo saneamento do original (chave de sessão validada, contadores inteiros, timestamp parseável — entrada inválida vira estado limpo, nunca crash).

## Portabilidade (a lição das issues do Headroom)

- Node puro, zero dependências, CommonJS `.cjs` como o resto.
- `spawn` com array de argumentos quando possível; quando o `CHECK:` é linha de shell, resolver o shell explicitamente (`cmd.exe /d /s /c` no Windows, `sh -c` no resto) e **gravar qual foi usado** na evidência.
- Match do `ESPERA:` em output combinado com normalização de `\r\n`.
- Nenhum exemplo no manual pode usar `grep`/`tail`/`sed` — o lint reforça isso.
- Timeout por portão (default 120s), processo morto = não cumprido, nunca pendurado.

## Portões deste próprio fluxo (esboço)

- P1: `portoes.cjs status` parseia o template sem executar nada — `CHECK` roda status num fixture e `ESPERA: PARSE OK`; prova de não-execução via fixture cujo CHECK criaria um arquivo-sentinela (o portão verifica que a sentinela NÃO existe).
- P2: portão com `echo ok` é rejeitado pelo lint — controle positivo do detector.
- P3: `rodar` num fixture com falha proposital sai com 1 e não marca o checkbox.
- P4: `ABANDONA:` sem razão é exit 2; com razão é exit 1 + `DEVOLUCAO OBRIGATORIA`.
- P5: no Windows (ou fixture simulando), `CHECK` com script Node roda e grava `cmd.exe` como shell na evidência.

## Perguntas abertas

- **P1:** onde vive `portoes.md` no layout real do repo — junto do plano do fluxo ou em `.rainforest/`? Claude Code decide olhando a árvore.
- **P2:** o hook de Stop atual já bloqueia por estágio; o bloqueio por portão entra no mesmo hook ou é checagem só no gate do `ok`? Começar só no gate é mais barato e reversível.

---

## Perguntas abertas — resolvidas em 2026-09-02

**P1 — onde vive o `portoes.md`: `docs/rainforest/portoes/<slug>.md`.**
A árvore real não tem `docs/rainforest/fluxos/`; tem quatro irmãos indexados pelo
mesmo slug — `design/`, `planos/`, `estado/`, `mapas/`. Um quinto irmão,
`portoes/`, mantém a convenção e dá de graça a coisa que os dois ganchos do
pipeline precisam: **o gate deriva o caminho do slug**, sem campo novo no estado,
sem config, sem argumento a mais. `estado.cjs` já recebe `--slug` em todo comando;
`portoes.cjs` passa a receber o arquivo por caminho explícito (para fixture de
teste) e o gate monta `docs/rainforest/portoes/<slug>.md` sozinho.

Consequência boa e não planejada: "o fluxo tem portões?" vira `existsSync` de um
caminho derivado, que é exatamente o teste que o desenho opt-in pede.

**P2 — o bloqueio por portão entra só no gate do `ok`.** É a recomendação do
próprio design ("mais barato e reversível") e ela se sustenta: o hook de Stop é
o lugar onde um defeito prende a sessão sem saída, e a guarda de 6 bloqueios
existe justamente porque esse risco é real. Gate de `ok` erra para o lado seguro
— o pior caso é um `ok` recusado, e a pessoa está na frente do teclado.

Fica **fora do escopo deste fluxo**, nomeado e não esquecido: a guarda de
progresso no hook de Stop (a seção acima continua valendo como desenho). Entra
quando houver evidência de que o gate do `ok` sozinho não segura — não antes.
