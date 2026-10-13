# Plano: executar com camadas, retomada por sentinela e painel do fluxo

Design: docs/rainforest/design/2026-10-13-executar-dag-painel.md

## Achados que contradizem o briefing (lidos no fonte, na base 5ebeb3e5)
- A recusa de arquivo compartilhado já existe em `scripts/conferir-fluxo.cjs` (`cmdCobertura`, linhas 338-350), mas só entre tarefas `paralela: sim`. A regra "paralela: sim exige depende de: nenhuma" está nas linhas 280-283. As duas passam a ser medidas por camada (D2, D3).
- `skills/executar/SKILL.md` tem 16381 B e `skills/plano/SKILL.md` tem 16380 B, com teto de 16384. Texto novo vai para `skills/executar/references/camadas-e-retomada.md`. No `plano/SKILL.md`, a frase sobre `paralela:` é reescrita sem crescer.
- `git commit -m X --trailer "Rainforest-Tarefa: <slug>#<n>"` passa por `gate-mensagem-commit`, `gate-staging-total`, `gate-git-verificacao` e `gate-publicacao-destino` (exit 0, medido na base). O trailer é lido por `git log --format='%(trailers:key=Rainforest-Tarefa,valueonly)'`.

## O que não pode quebrar
- `bash scripts/testa-conferir-fluxo.sh` e `bash scripts/testa-estado.sh` verdes. Planos já fechados continuam passando na cobertura: `paralela:` vira aviso, não recusa.
- O `marcar` nunca muda de exit por causa do painel. Falha ao gerar o painel vira aviso no stderr.
- `bash scripts/testa-teto-skills.sh` verde e `node scripts/orcamento.cjs` sem mudança de `description`.
- O estado JSON não é fonte da integração: o `retomar` só declara `integrada` com o trailer presente no git.

## Decisões assumidas pelo plano (técnicas; o design não fixa)
- As camadas moram em `scripts/lib/camadas.cjs`, que exporta `calcularCamadas(tarefas)`. Entrada: `[{numero, dependeDe: number[], arquivos: string[]}]`. Saída: `{camadas: number[][], conflitos: [{camada, a, b, arquivo}]}`. Ciclo ou dependência inexistente lança `ErroCamadas` com as tarefas nomeadas. Dentro de cada camada, as tarefas saem em ordem numérica.
- Conflito de arquivo por camada usa o mesmo `globMatches` que a cobertura já usa (duas entradas casam se uma casa com a outra como glob, ou se são iguais).
- `conferir-fluxo.cjs camadas --slug <s>` imprime o JSON das camadas. Exit 0 sem conflito, 2 com conflito, ciclo ou dependência inexistente.
- `retomar` lê o trailer em `git log <base>..HEAD` da branch atual, com `<base>` = `git merge-base HEAD origin/<branch padrão>`. Sai em JSON: `{tarefas: [{numero, estado, camada}], re_marcar: [n], redespachar: [n], proxima_camada: [n] | null}`. Exit 0. Slug inexistente, plano ausente ou ciclo sai 1.
- `integrada` não contada = trailer presente e número maior que `executar.tarefas_ok`, ou ausente de `executar.integradas`, se a lista existir. `marcar --estagio executar` aceita `integradas: [n]` no `--json`, fundido e persistente como `carimbos`.
- O painel é gerado por `scripts/painel-fluxo.cjs gerar --slug <s>`, HTML auto-contido sem rede. O `estado.cjs` o chama ao fim de `marcar` dos três estágios, com `try` que só avisa. A raiz de dados vem de `resolverRaiz` (`hooks/lib/raiz.cjs`), como no `gate-teto-despachos`.

## Em aberto
- Nada.

## Tarefas

### 1. Camadas do `depende de:` e recusa por camada [tipo: implementar]
atende: D2, D3, D8
arquivos: `scripts/lib/camadas.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/testa-camadas.sh`, `scripts/testa-conferir-fluxo.sh`
depende de: nenhuma
prova: `bash scripts/testa-camadas.sh`
mutacao:
  arquivo: `scripts/lib/camadas.cjs`
  de: `if (prontas.length === 0) throw new ErroCamadas(`
  para: `if (false) throw new ErroCamadas(`
  bateria: `bash scripts/testa-camadas.sh`
  fixture: `testa-camadas.sh, secao "ciclo 1->2->1 recusa nomeando as duas"`
pronto quando: com planos reais em `docs/rainforest/planos/` copiados para um repo-caixa e alterados pela bateria, `node scripts/conferir-fluxo.cjs camadas --slug <s>`:
- sai 0 com `{"camadas":[[1,2],[3]]...}` para 1 e 2 sem dependência e 3 dependendo de ambas;
- sai 2 nomeando as duas tarefas para ciclo 1→2→1;
- sai 2 nomeando `depende de: 9` inexistente;
- sai 2 com `conflitos` nomeando o arquivo para 1 e 2 na mesma camada com `arquivos:` em comum, inclusive quando um é glob que casa o outro;
- sai 0 quando as mesmas duas tarefas estão em camadas diferentes.

Além disso, `node scripts/conferir-fluxo.cjs cobertura --slug <s>`:
- recusa (exit 2) os mesmos três defeitos;
- aceita plano sem nenhum `paralela:`;
- aceita, com uma linha de aviso no stderr, plano com `paralela: sim` em tarefa que depende de outra;
- continua aceitando `docs/rainforest/planos/2026-10-13-fechar-push-merge.md` e `docs/rainforest/planos/2026-10-10-flaky-teto.md` copiados como estão.

Provado por `bash scripts/testa-camadas.sh` com a última linha `ok: N   falhou: 0` e por `bash scripts/testa-conferir-fluxo.sh` saindo 0.

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita: Kahn com a lista `prontas` (tarefas cujas dependências já saíram). O laço termina quando todas saíram, e `if (prontas.length === 0) throw new ErroCamadas(` aparece uma vez, no ramo de ciclo. Parada (D8): a recusa confere só o que está declarado em `depende de:` e `arquivos:`.

### 2. `estado.cjs retomar` e o trailer de integração [tipo: implementar]
atende: D1, D4, D5
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-retomar.sh`, `scripts/testa-estado.sh`
depende de: 1
prova: `bash scripts/testa-estado-retomar.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (comTrailer.has(n) && !contadas.has(n)) reMarcar.push(n);`
  para: `if (comTrailer.has(n) && contadas.has(n)) reMarcar.push(n);`
  bateria: `bash scripts/testa-estado-retomar.sh`
  fixture: `testa-estado-retomar.sh, secao "tarefa integrada e nao marcada vai para re_marcar"`
pronto quando: num repo-caixa com `origin` bare, branch `fluxo/x` com o fluxo aberto por `estado.cjs iniciar`, plano de 3 tarefas (1 e 2 sem dependência, 3 dependendo das duas) e `executar` aberto, `node scripts/estado.cjs retomar --slug <s>`:
- sem nenhum commit com trailer: devolve as 3 `pendente`, `proxima_camada: [1,2]`, listas vazias;
- com commit `git commit --trailer "Rainforest-Tarefa: <s>#1"` e `marcar` com `integradas:[1]`: tarefa 1 `integrada`, `proxima_camada: [2]`;
- com o commit da tarefa 2 com trailer e sem `marcar`: `re_marcar: [2]`;
- com `em_voo` registrando a tarefa 3 e sem trailer dela: `redespachar: [3]`;
- com trailer de outro slug (`<outro>#2`): não conta para este fluxo;
- com as 3 integradas e marcadas: `proxima_camada: null`;
- com slug inexistente ou com o plano ausente: sai 1.

E `marcar --estagio executar --json '{"integradas":[1]}'` seguido de `{"integradas":[2]}` grava `[1,2]`. Provado por `bash scripts/testa-estado-retomar.sh` com `ok: N   falhou: 0` e por `bash scripts/testa-estado.sh` saindo 0.

Nota: código a nascer. Forma prescrita: `comTrailer` e `contadas` são `Set` de números, e a linha `if (comTrailer.has(n) && !contadas.has(n)) reMarcar.push(n);` aparece uma vez. `retomar` entra em `FLAGS_POR_SUBCOMANDO` como `retomar: ['slug']`. As camadas vêm de `require('./lib/camadas.cjs')`. A bateria monta a caixa com `mktemp -d` fora do worktree, limpa `GIT_*` herdados e configura `user.*` só na caixa.

### 3. Painel HTML do fluxo [tipo: implementar]
atende: D6, D7
arquivos: `scripts/painel-fluxo.cjs`, `scripts/estado.cjs`, `scripts/testa-painel-fluxo.sh`
depende de: 2
prova: `bash scripts/testa-painel-fluxo.sh`
mutacao:
  arquivo: `scripts/painel-fluxo.cjs`
  de: `.replace(/&/g, '&amp;').replace(/</g, '&lt;')`
  para: `.replace(/&/g, '&amp;')`
  bateria: `bash scripts/testa-painel-fluxo.sh`
  fixture: `testa-painel-fluxo.sh, secao "titulo com <script> sai escapado"`
pronto quando: na mesma caixa da tarefa 2, com `RFM_ROOT` apontando para uma pasta da caixa:
- `node scripts/estado.cjs marcar --slug <s> --estagio executar --status parcial --json '{"integradas":[1]}'` sai 0 e cria `<RFM_ROOT>/fluxos/<s>/painel.html`;
- esse HTML tem um cartão por tarefa do plano, com número, camada e estado (`integrada` para a 1, `pendente` para as outras), o estágio atual do fluxo e a data do último `marcar`;
- um `marcar` de `revisar` regenera o arquivo, com o mtime maior e o veredito visível;
- título de tarefa com `<script>` sai como `&lt;script&gt;`;
- o HTML não referencia URL externa (`http`);
- com `RFM_ROOT` apontando para um arquivo em vez de pasta, o `marcar` ainda sai 0 e imprime `aviso: painel` no stderr;
- `node scripts/painel-fluxo.cjs gerar --slug <s>` sozinho imprime o caminho do arquivo gerado.

A pergunta da superfície humana: quem abre o painel vê, sem rolar, qual tarefa está em voo, qual falta e se o fluxo parou. A bateria confere que os três estados aparecem como texto, não só como cor. Provado por `bash scripts/testa-painel-fluxo.sh` com `ok: N   falhou: 0`.

Nota: o painel reaproveita a função de estado por tarefa da tarefa 2 (exportada pelo `estado.cjs` ou movida para `scripts/lib/`, sem duplicar), e nenhum caso de teste afirma sobre o texto do fonte.

### 4. Skills, README, CHANGELOG e versão 1.65.0 [tipo: docs]
atende: D1, D2, D4, D5, D6
arquivos: `skills/executar/SKILL.md`, `skills/executar/references/camadas-e-retomada.md`, `skills/plano/SKILL.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `scripts/baterias-obrigatorias.txt`, `scripts/contrato-plugin-codex.cjs`
depende de: 3
mutacao: n/a
  motivo: texto de skill e de documentação, sem comportamento a inverter; a falsificação é a coerência com os scripts e com o design.
pronto quando: com os scripts das tarefas 1 a 3 na branch, as quatro coisas abaixo valem.
- **`camadas-e-retomada.md`:** manda despachar por camada, a partir do `conferir-fluxo camadas`. Fixa a ordem conferência → `git commit --trailer "Rainforest-Tarefa: <slug>#<n>"` → `marcar` com `integradas`. Manda rodar `estado.cjs retomar` ao pegar um `executar` pela metade e agir em `re_marcar` e `redespachar`. Diz onde fica o painel e quando a sessão chama `PushNotification` (teto, `flaky`, fim).
- **Ponteiros:** `executar/SKILL.md` aponta para esse arquivo, e `plano/SKILL.md` deixa de exigir `paralela:`, os dois sem passar de 16384 B.
- **README e CHANGELOG:** o README cita os três comandos novos, e o CHANGELOG tem a entrada 1.65.0.
- **Versão e baterias:** a versão é 1.65.0 em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` e no selo do README. As três baterias novas estão em `scripts/baterias-obrigatorias.txt`.

Cada comando e campo citado nas skills existe nos scripts (`conferir-fluxo.cjs camadas`, `estado.cjs retomar`, `integradas`, `painel-fluxo.cjs gerar`). Provado por `bash scripts/testa-versao.sh`, `bash scripts/testa-teto-skills.sh`, `bash scripts/testa-plugin-codex.sh`, `node scripts/orcamento.cjs` e `bash scripts/testa-varrer-baterias.sh` saindo 0.

Emenda (executar, tarefa 1, 2026-10-13): conflito de arquivo na mesma camada em que alguma das duas tarefas declara `paralela:` é aviso, não recusa (D2); sem `paralela:` em nenhuma das duas, recusa (D3). `scripts/testa-conferir-fluxo.sh` entra na tarefa 1: a asserção da mensagem `paralela: sim mas depende de` passa a conferir o aviso, e a sabotagem da seção 7 copia também `scripts/lib/`. Critério acrescido: `bash scripts/testa-conferir-fluxo.sh` volta a sair 0. Ajuste da integração (volta 2): só `paralela: nao` explícito amolece o conflito para aviso; `paralela: sim` com arquivo em comum continua recusa, como na base — o plano de 2026-08-21 (tarefas 3 e 8, ambas `sim`) já era recusado pela base `5ebeb3e5` e continua sendo.

Emenda (executar, tarefa 2, 2026-10-13): `scripts/testa-estado.sh` entra na tarefa 2 — a caixa dela passa a copiar `scripts/lib/camadas.cjs`, que o `conferir-fluxo.cjs` importa desde a tarefa 1 (sem a cópia, 15 casos caíam com o `marcar plano ok` falhando). A tarefa 1 só rodou `testa-conferir-fluxo.sh`; a regressão apareceu aqui.

Emenda (executar, tarefa 4, 2026-10-13): `skills/plano/references/recusas-da-cobertura.md` entra na tarefa 4. Ela listava a recusa antiga ("`paralela: sim` com `depende de`" e "duas tarefas paralelas"), que deixou de valer com a tarefa 1; agora lista ciclo, dependência inexistente e conflito por camada.

Emenda (revisar, volta 1, 2026-10-13): seis achados corrigidos na branch.
- O `depende de:` passa a ler só a lista do começo. `nenhuma` seguida de prosa vale vazio, e `a-b` é intervalo (tarefa 1). O plano `2026-09-08-validar-ponte-codex-ao-vivo` voltou a passar na cobertura.
- O `retomar` devolve `contadas_sem_trailer` e, sem `origin/<padrão>`, lê o trailer no histórico do HEAD (tarefa 2).
- O cartão do painel traz a iteração do laço, pelo carimbo mais recente. O veredito fica no resumo, porque o `revisar` julga a branch, não a tarefa: D6 fica cumprido assim (tarefa 3).
- A doc de `integradas` diz que o `ok` não o apaga (tarefa 4).
- Critério acrescido: `testa-camadas.sh` cobre `nenhuma` com prosa, lista com parêntese e intervalo. `testa-estado-retomar.sh` cobre `proxima_camada` com tarefa não marcada, `em_voo` com trailer, `contadas_sem_trailer` e repo sem `origin`. `testa-painel-fluxo.sh` cobre a iteração no cartão.

Emenda (revisar, volta 2, 2026-10-13): dois achados.
- O parser da volta 1 cortava a lista no primeiro `(`, e `1 (design), 2` perdia o 2. Agora os grupos entre parênteses saem e os itens são lidos até o primeiro que não é número (tarefa 1). No corpus, 96 formas distintas de `depende de:`, e só `todas` recusa, como a base já recusava.
- `testa-estado-retomar.sh` passa a assertar `proxima_camada` com tarefa contada sem trailer (tarefa 2). Critério acrescido: `testa-camadas.sh` cobre `1 (design), 2` e `2, após 17:41`.
