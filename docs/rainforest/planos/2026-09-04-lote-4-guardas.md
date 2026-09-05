# Plano: Lote 4 — guardas que afirmam o que nao mediram

Design: docs/rainforest/design/2026-09-04-lote-4-guardas.md

> Nota de forma: este plano **não cola** o literal de um SHA-1, de um telefone
> fictício nem de uma URL de clone autenticado — o gate de publicação recusa o
> próprio arquivo que descreve o conserto dele (medido em 2026-09-04, três
> recusas ao escrever esta versão; é a mesma demonstração que a #173 registra).
> Os critérios nomeiam a **forma** da entrada; o literal mora na bateria de cada
> tarefa, que é onde ele precisa estar.

## O que não pode quebrar
- Nenhuma bateria que hoje está verde fica vermelha (baseline medido antes do
  despacho, colado no estado do fluxo).
- O gate de publicação continua barrando dado sensível **novo**: JID real,
  caminho de home, credencial literal. Afrouxar o gate é o modo de falha caro
  deste lote inteiro.
- Os três gates por texto de comando continuam barrando o que já barravam:
  `git add -A` na janela principal, `"git" add -A` (R20), escrita de subagente
  fora de worktree.
- `gh pr create` com palavra-chave de fechamento em inglês sem evidência
  continua barrado — a extensão da tarefa 3 acrescenta recusa, nunca remove.
- Referência deliberada a Issue ("Segue #73", "Ver #73") continua passando.
- Nenhum script passa a escrever fora do worktree em que roda.

## Tarefas

### 1. Gate de publicação julga o que o commit introduz, e para de acusar indireção e hash [tipo: implementar]
atende: D2, D3, D4, D5, D6
arquivos: `hooks/gate-publicacao-destino.cjs`, `scripts/conferir-publicacao.cjs`, `hooks/testa-gate-publicacao-destino.sh`, `scripts/testa-conferir-publicacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (achadoJaEstaNoPai(dir, nome, a, conteudo)) continue;`
  para: `if (false) continue;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: `hooks/testa-gate-publicacao-destino.sh, caso novo "commit com achado que ja esta no pai PASSA"`
pronto quando: num repositório git real com um arquivo já commitado que contém
um caminho de home do Windows (achado `[caminho-de-home]`), o payload de
`PreToolUse` do harness para `Bash` com `git commit -m x`, com esse mesmo
arquivo em stage e **sem alteração no trecho**, sai `exit 0`; e o mesmo payload,
depois de acrescentar ao arquivo uma **linha nova** com outro caminho de home,
sai `exit 2` — provado por `printf '%s' "<payload>" | node
hooks/gate-publicacao-destino.cjs; echo $?` nas duas formas. E: uma linha no
formato `"head"` dos arquivos de `docs/rainforest/estado/`, com um SHA-1 de 40
caracteres hexadecimais, deixa de produzir achado `telefone` em
`node scripts/conferir-publicacao.cjs - --json`, enquanto um telefone brasileiro
em forma canônica (DDD entre parênteses, nove dígitos) continua produzindo. E:
uma URL de clone autenticado cujo lugar da senha traz uma **referência** de
variável (chaves ou cifrão) deixa de produzir achado `credencial`, enquanto a
mesma URL com valor literal de 40 caracteres continua produzindo.

### 2. Tokenizador: wrapper citado conta, e `bash <script>` deixa de ser ilegível [tipo: implementar]
atende: D7, D17
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/gate-worktree.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `WRAPPERS_QUE_REPASSAM.has(nomeDeWrapper(toks[i]))`
  para: `(!toks[i].q && WRAPPERS_QUE_REPASSAM.has(toks[i].v))`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: `hooks/testa-gate-staging-total.sh, bloco R21 (caso do wrapper citado antes de git add -A)`
pronto quando: na janela principal, dentro de um repositório git, o comando com
o wrapper `env` **citado** antes de `git add -A` é barrado com `exit 2` pelo
`gate-staging-total.cjs` — hoje sai `0` — e `grep -rn "env FOO=1 git add" docs/`,
que tem o mesmo texto como **argumento**, continua saindo `0`; provado por
`printf '%s' "<payload Bash com cada comando>" | node
hooks/gate-staging-total.cjs; echo $?`. E: o payload de `Bash` com
`bash hooks/testa-config.sh` sai `exit 0` no `gate-fechar-issue.cjs` — hoje sai
`2` com "ilegível" — enquanto `bash -c` com uma variável dentro continua saindo
`2`.

### 3. O gate de fechamento reconhece a palavra-chave falsa em português, e olha `gh issue create|comment` [tipo: implementar]
atende: D8
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/lib/config.cjs`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const FALSA_CHAVE =`
  para: `const FALSA_CHAVE = /(?!)/; const NAO_USADA =`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `hooks/testa-gate-fechar-issue.sh, caso novo "gh pr create com verbo portugues antes de #N -> exit 2"`
pronto quando: `gh pr create --body "Fecha #73."` sai `exit 2` com mensagem que
nomeia as palavras que o GitHub reconhece em inglês e oferece a troca; `gh pr
create --body "Segue #73. Ver #74."` sai `exit 0`; `gh issue comment 73 --body
"Fecha #73"` sai `exit 2` (hoje `gh issue comment` não é olhado por ramo
nenhum); e `gh pr create --body-file <arquivo cujo corpo tem o verbo português
antes de #N>` sai `exit 2`. Provado por `printf '%s' "<payload>" | node
hooks/gate-fechar-issue.cjs; echo $?` nas quatro formas.

### 4. `conferir-versao.cjs` mede o repositório do cwd [tipo: implementar]
atende: D9, D10
arquivos: `scripts/conferir-versao.cjs`, `scripts/testa-conferir-versao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-versao.cjs`
  de: `const RAIZ = raizDoCwd() || path.resolve(__dirname, "..");`
  para: `const RAIZ = path.resolve(__dirname, "..");`
  bateria: `bash scripts/testa-conferir-versao.sh`
  fixture: `scripts/testa-conferir-versao.sh, caso novo "script copiado para pasta sem git mede o repositorio do cwd"`
pronto quando: com o script copiado para uma pasta que **não** é repositório git
(a forma do cache do plugin instalado) e o cwd num repositório de plugin com
commits além do último bump, `node <copia>/conferir-versao.cjs --json` sai com o
mesmo exit e a mesma contagem de commits que a execução de dentro do clone —
hoje sai `0` com "esta pasta nao e repositorio git". E, num repositório git
**sem** `.claude-plugin/plugin.json`, a mensagem diz que o repositório não é um
plugin, não que a pasta não é repositório git.

### 5. `limpar-branches --remoto` apaga toda classe com remoto vivo [tipo: implementar]
atende: D11
arquivos: `scripts/limpar-branches.cjs`, `scripts/testa-limpar-branches.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/limpar-branches.cjs`
  de: `const COM_REMOTO_VIVO = new Set(['resolvida-remota', 'mergeada-por-squash']);`
  para: `const COM_REMOTO_VIVO = new Set(['resolvida-remota']);`
  bateria: `bash scripts/testa-limpar-branches.sh`
  fixture: `scripts/testa-limpar-branches.sh, caso novo "--remoto apaga o remoto da mergeada-por-squash"`
pronto quando: num repositório com remoto bare local e uma branch classificada
`mergeada-por-squash` (commits ausentes da base, merge confirmado pelo `gh`
dublado, remoto vivo), `node scripts/limpar-branches.cjs --remover --forcar
--remoto` apaga a branch remota — `git ls-remote --heads origin` deixa de
listá-la — e a saída não contém "(nenhuma tinha remoto vivo para apagar)".

### 6. A seção 9 do `testa-triagem.sh` afirma forma, não número [tipo: teste]
atende: D12
arquivos: `scripts/testa-triagem.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/testa-triagem.sh`
  de: `-ge 100`
  para: `-ge 100000`
  bateria: `bash scripts/testa-triagem.sh`
  fixture: `scripts/testa-triagem.sh, secao 9 (assercao de fonte grande do IAG67M12.prw)`
pronto quando: nesta máquina, onde a pasta `inovacao` existe e o fonte de
referência mudou de 219 para 223 funções, `bash scripts/testa-triagem.sh` sai
`0` — hoje sai `1` com "esperava '219', veio '223'" — e a seção continua
afirmando a **classe** (`logica`) daquele fonte, de modo que classificá-lo como
`dado-como-codigo` deixaria a bateria vermelha.

### 7. `limpar-worktrees.cjs` reconhece registro travado cujo diretório sumiu [tipo: implementar]
atende: D13
arquivos: `scripts/limpar-worktrees.cjs`, `scripts/testa-limpar-worktrees.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/limpar-worktrees.cjs`
  de: `if (classe === "fantasma-travado" && remover) {`
  para: `if (false && remover) {`
  bateria: `bash scripts/testa-limpar-worktrees.sh`
  fixture: `scripts/testa-limpar-worktrees.sh, caso novo "registro travado com diretorio ausente e destravado, removido e podado"`
pronto quando: num repositório com um worktree registrado, **travado**
(`git worktree lock`) e com o diretório apagado do disco — a forma exata das 12
entradas do incidente de 2026-09-04 —, `node scripts/limpar-worktrees.cjs
--remover` classifica a entrada, destrava, remove e poda: depois dele
`git worktree list` não a lista e o comando sai `0`, enquanto `git worktree
prune` sozinho, antes, deixava a entrada de pé. Falha de remoção sai nomeada na
saída, nunca em silêncio.

### 8. Regra 11 e briefing: agente que edita não se retoma, e a base se confere por `merge-base` [tipo: docs]
atende: D14, D15
arquivos: `skills/rainforest-mind/references/regra-11.md`, `skills/executar/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de regra não tem ramo executável a inverter; a falsificação
  desta tarefa é a coerência com o design (D14 e D15) e com a interface real do
  `git`, conferida no critério abaixo.
pronto quando: os dois arquivos prescrevem `git merge-base --is-ancestor HEAD
<base>` como a conferência de base do briefing, e **nenhum** dos dois ainda
manda o briefing listar hashes velhos conhecidos — provado por
`grep -n "merge-base --is-ancestor" skills/rainforest-mind/references/regra-11.md
skills/executar/SKILL.md` trazendo linha nos dois e `grep -rn "hashes velhos
conhecidos" skills/` não trazendo nenhuma; o comando prescrito roda de verdade
(`git merge-base --is-ancestor HEAD origin/main; echo $?` devolve `0` ou `1`,
nunca erro de uso); e os dois arquivos dizem que agente que edita **não** se
retoma por `SendMessage`, mandando redespachar com briefing corrigido.

### 9. Despacho fica registrado, e o turno não acaba com agente em voo [tipo: implementar]
atende: D16
arquivos: `scripts/estado.cjs`, `hooks/gate-agente-em-voo.cjs`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `hooks/testa-gate-agente-em-voo.sh`, `skills/executar/SKILL.md`, `skills/revisar/SKILL.md`
depende de: 3, 8
paralela: nao
mutacao:
  arquivo: `hooks/gate-agente-em-voo.cjs`
  de: `process.exit(2);`
  para: `process.exit(0);`
  bateria: `bash hooks/testa-gate-agente-em-voo.sh`
  fixture: `hooks/testa-gate-agente-em-voo.sh, caso "estagio com em_voo e stop_hook_active false -> exit 2"`
pronto quando: com o estado de um fluxo marcado `--estagio revisar --status
parcial` e um `em_voo` declarando um agente, o payload de `Stop` que o harness
envia (com `stop_hook_active` falso) sai `exit 2` com mensagem nomeando o agente
em voo e o estágio; o **mesmo** payload com `stop_hook_active` verdadeiro sai
`exit 0` (não vira laço); e depois de `--estagio revisar --status ok` com
evidência, o payload de `Stop` volta a sair `exit 0` — provado por
`printf '%s' "<payload>" | node hooks/gate-agente-em-voo.cjs; echo $?` nas três
formas.

### 10. A #182 recebe a correção do diagnóstico antes de fechar [tipo: docs]
atende: D1
arquivos: `docs/rainforest/design/2026-09-04-lote-4-guardas.md`
depende de: 7
paralela: nao
mutacao: n/a
  motivo: a tarefa é um comentário em Issue do GitHub — não há ramo de código a
  inverter; a falsificação é o comentário citar o comando e a saída que refutam
  o diagnóstico, conferidos no critério.
pronto quando: a Issue #182 tem comentário que (a) cola
`grep -n worktree scripts/conferir-mutacao.cjs` sem saída e (b) nomeia
`scripts/limpar-worktrees.cjs` como o destino real do conserto — provado por
`gh issue view 182 --comments` mostrando o comentário com os dois itens.

### 11. O instrumento confere registro de hook lendo o JSON, não contando linhas [tipo: teste]
atende: nasceu na revisão (2026-09-05), não estava no design
arquivos: `hooks/testa-memoria-marca.sh`
depende de: 9
paralela: não (a tarefa 9 é quem cria o sintoma)
mutacao:
  arquivo: `hooks/testa-memoria-marca.sh`
  de: `process.exit(achou ? 0 : 1);`
  para: `process.exit(0);`
  bateria: `bash hooks/testa-memoria-marca.sh`
  fixture: `hooks/testa-memoria-marca.sh, testes 2 a 4 (registro em PostToolUse, Stop e SessionEnd)`
pronto quando: `bash hooks/testa-memoria-marca.sh` sai `0` com o `hooks.json`
atual — hoje sai `1` com "memoria-marca.cjs não está em Stop", porque a tarefa
9 acrescentou um grupo em `Stop` e empurrou o hook procurado para fora da
janela de 15 linhas do `grep -A`; e `grep -A 15 '"Stop"' hooks/hooks.json |
grep -c memoria-marca.cjs` devolve `0`, provando que a forma antiga já não
enxerga o registro que existe.

### 12. Versão sobe para 1.4.0 [tipo: release]
atende: a regra do `conferir-versao.cjs`, que recusa acúmulo além do teto
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: todas
paralela: não
mutacao: n/a
  motivo: número de versão não tem ramo executável a inverter; a falsificação
  é o próprio `conferir-versao.cjs`, que recusa antes e aceita depois.
pronto quando: `node scripts/conferir-versao.cjs` sai `0` — antes do bump ele
saía `2` com "38 commit(s) em 'HEAD' desde o ultimo bump de versao (5d1e81a),
e o teto e 5" —, e o número aparece nos **dois** lugares que o `CONTRIBUTING.md`
diz que andam juntos: `.claude-plugin/plugin.json` e o badge do `README.md`.
MINOR e não PATCH porque entrou comportamento novo (campo `em_voo`) e um hook
novo (`Stop`), sem quebrar interface.
