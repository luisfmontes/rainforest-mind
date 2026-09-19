# Handover Codex — Rainforest Mind multihost 1.13.2

> **Reancorado na `origin/main` 1.19.2 em 2026-09-19.** A base da entrega saiu de
> `068468fb` (1.13.2) para `2adbae270782a5a36512c28a5c2a5354ba05c73e` (1.19.2),
> depois da análise de sobreposição que este handover exige. Todo hash e toda
> versão `1.13.2` citados nas seções antigas são **registro histórico**: o estado
> corrente está na seção "Reancoragem na origin/main 1.19.2" do portão do fluxo.
> Derive sempre o HEAD e a base correntes com Git, nunca copie hash de prosa.

> **Atualizado em 2026-09-19, depois da sessão Claude.** A contraprova do hook
> foi concluída e passou, a instalação final limpa foi restaurada e `executar`
> fechou de novo em `ok`, 9/9. As seções abaixo até "Piloto histórica"
> descrevem o estado **anterior** a essa sessão e ficam como registro; o estado
> corrente está em "Estado em 2026-09-19, depois da sessão Claude", no fim
> deste arquivo, e é por onde o Codex deve começar.

Atualizado em 2026-09-19. Este documento retoma a entrega local que adapta o
Rainforest Mind ao Codex sem bifurcar o produto.

**Destinatário deste handover: uma nova sessão do Claude Code.** Continue o
trabalho no Claude para poupar tokens do Codex. Não transfira a implementação
ou a revisão para uma sessão/agente Codex; invoque o binário `codex` somente na
sessão efêmera de contraprova descrita abaixo, porque ela mede o host real que o
plugin precisa suportar.

**Divisão combinada:** o Claude executa a contraprova, restaura a instalação
final, corrige o rastro e fecha novamente `executar`. Então ele para e devolve
a branch ao Codex; o Codex fará a revisão final independente e, se ela passar,
o estágio `verificar`. A proibição de publicar ou mesclar
na `main` continua valendo também depois dessa revisão, até novo aval do usuário.

## Resultado corrente

O Rainforest Mind continua sendo **um único repositório e um único plugin** para
Claude, Codex e o futuro Gemini. O núcleo, as skills e as políticas são
compartilhados; cada host recebe somente o adaptador fino necessário. Nesta
entrega, Claude e Codex estão comprovados. Gemini permanece explicitamente adiado:
nenhum manifesto, hook ou payload Gemini foi criado.

A versão final da fonte continua exatamente em `1.13.2`. O plano existe, está
aprovado e contém nove tarefas; o arquivo é
`docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`. O último commit
antes desta atualização de handover é
`fd0c8501d479653eccd79b3d74834bc26d04fd31`; derive o HEAD corrente com Git. Esse
commit registra a revisão independente final com **zero achados** sobre o candidato
`52245a7fd0e7c6f7a74dd56b6a7310bd1fb753cc`.

O fluxo, porém, **não está pronto para fechar**. O estágio `verificar` foi
marcado `reprovado` durante uma repetição da T6/T7, e isso reabriu `executar`
como `parcial`. A reprovação veio de uma sessão Codex em fixture criada pelo
usuário isolado `CodexSandboxOffline`: dentro do hook, `git rev-parse --git-dir`
saiu 128 por `dubious ownership`, o núcleo interpretou o diretório como fora de
Git e deixou `git add "-A"` chegar ao executor. O comando ainda falhou depois,
ao tentar criar `.git/index.lock`; portanto aquela sessão não provou o bloqueio.

O diagnóstico posterior mostrou que parser, configuração e adaptador estão
corretos: `gateLigado=true`, motivo `git add -A`, payload real idêntico ao
fixture e o adaptador manual devolvendo `permissionDecision: "deny"`. A causa
do falso vermelho foi confirmada no stderr do Git:

```text
fatal: detected dubious ownership in repository at '<fixture>'
owned by: CodexSandboxOffline
current user: Luis
```

Uma fixture de contraprova já foi criada fora do sandbox, com proprietário
correto, em:

```text
C:\Users\Luis\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\t6-cachebuster-session-host
```

Ela responde `.git` a `git rev-parse --git-dir` e contém somente
`?? deny-control.txt`. A próxima sessão deve repetir nela o teste real do hook.
Não marque `verificar=ok` antes dessa contraprova.

Neste instante o marketplace **não está na instalação final**: ele aponta
deliberadamente para o export diagnóstico
`C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-diagnostic`,
versão `1.13.2+codex.20260915000908`. Esse pacote contém instrumentação apenas
para diagnóstico e nunca deve ser commitado nem tratado como release. Depois da
contraprova, restaure o marketplace e o plugin exato pelo export limpo
`C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.13.2`.

## Retomada segura

O worktree de entrega continua com o nome histórico `codex-multihost-1.11`, mas
a branch real é `codex/multihost-1.13`:

```powershell
$entrega = 'C:\Projetos\rainforest-mind\.claude\worktrees\codex-multihost-1.11'
$origemFinal = 'C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.13.2'
$origemDiagnostica = 'C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-diagnostic'
$base = '068468fb956b8d606e9af1800aaa91dd399fdeb8'

if (-not (Test-Path -LiteralPath $entrega -PathType Container)) {
  throw "ABORTO: worktree de entrega ausente ou não é diretório: $entrega"
}

$entregaCanonica = [System.IO.Path]::GetFullPath(
  (Resolve-Path -LiteralPath $entrega -ErrorAction Stop).Path
).TrimEnd([char[]]@('\', '/'))
$topLevelInformado = git -C $entrega rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevelInformado)) {
  throw "ABORTO: Git não resolveu o top-level da worktree de entrega"
}
$topLevelCanonico = [System.IO.Path]::GetFullPath(
  (Resolve-Path -LiteralPath ($topLevelInformado.Trim()) -ErrorAction Stop).Path
).TrimEnd([char[]]@('\', '/'))
if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
  $topLevelCanonico,
  $entregaCanonica
)) {
  throw "ABORTO: top-level Git inesperado; esperado='$entregaCanonica'; obtido='$topLevelCanonico'"
}

Test-Path -LiteralPath $origemFinal
Test-Path -LiteralPath $origemDiagnostica
$branch = git -C $entrega branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch.Trim() -ne 'codex/multihost-1.13') {
  throw "ABORTO: branch de entrega inesperada: '$branch'"
}
$head = git -C $entrega rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') {
  throw "ABORTO: HEAD da entrega não pôde ser derivado"
}
git -C $entrega merge-base --is-ancestor $base $head
if ($LASTEXITCODE -ne 0) {
  throw "ABORTO: base '$base' não é ancestral do HEAD '$head'"
}
"branch=$branch"
"head=$head"
"base_ancestral=True"
codex plugin marketplace list
codex plugin list
```

O bloco é deliberadamente fail-closed: `Test-Path = False`, falha ao resolver
qualquer caminho ou top-level canônico diferente de `$entrega` interrompe a
retomada antes das consultas de branch, HEAD e ancestralidade. Assim, o Git
nunca pode subir até o repositório pai e validar a `main` por engano.

`git rev-parse HEAD` é a fonte de verdade para o HEAD corrente. Antes da T8, a
branch estava em `810b0372df0f0ade2445645235d19dd261022550`, commit que integra
a T7 verde. **Esse hash é uma âncora de entrada, não o HEAD final congelado:** o
commit da própria T8 e sua integração necessariamente produzirão um descendente.

Confirme também que a base permanece ancestral e que os dois manifestos têm a
versão esperada:

```powershell
git -C $entrega cat-file -e "$base^{commit}"
git -C $entrega show "$base`:.claude-plugin/plugin.json" |
  Select-String '"version": "1.13.2"'
(Get-Content -Raw "$entrega\.claude-plugin\plugin.json" | ConvertFrom-Json).version
(Get-Content -Raw "$entrega\.codex-plugin\plugin.json" | ConvertFrom-Json).version
```

A base desta entrega é `origin/main` em
`068468fb956b8d606e9af1800aaa91dd399fdeb8`, versão `1.13.2`. Não substitua essa
âncora por um hash mais novo sem repetir a análise de sobreposição e reancoragem.

## Documentos do fluxo

O slug conserva `1-11` porque o trabalho começou sobre 1.11, passou por 1.12 e
foi entregue sobre 1.13.2:

- Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`
- Plano: `docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`
- Estado: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`
- Portão: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`
- Mapa: `docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md`

Valide os caminhos no worktree de entrega:

```powershell
@(
  'docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json',
  'docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md'
) | ForEach-Object { "$_=$(Test-Path -LiteralPath (Join-Path $entrega $_))" }
```

## Evidência que importa

A T6 reaberta instalou o cachebuster
`1.13.2+codex.20260913114653`, enumerou 19 skills físicas mais a projeção
`source-command-saude` e bloqueou `git add "-A"` em uma sessão Codex nova. Os
dois manifestos foram restaurados byte a byte para `1.13.2`.

A T7 fez uma reinstalação da versão exata `1.13.2` e validou o payload de
produto sem casos pulados. A palavra “limpa” usada na evidência original ficou
invalidada depois: a origem era um checkout e a enumeração sem `-Force` omitiu
o `.git` copiado. Os números abaixo permanecem evidência histórica dos arquivos
de produto, não prova final de higiene da origem:

- 702 arquivos rastreados presentes no cache, zero ausentes e zero SHA-256
  divergentes;
- agregado fonte/cache:
  `5fd4319558ce9c5134a8f554d6f985dd1fae855977f645058dc41494d2733e6d`;
- único extra permitido:
  `.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`, SHA-256
  `321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339`,
  derivado de `commands/saude.md`, SHA-256
  `f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6`;
- skill instalada invocável;
- `git status --short` e `git add -- "-A"` permitidos;
- `git add "-A"` e `bash -c "git status; git add -A"` negados pelo hook;
- JSON malformado recusado com `deny`, stderr vazio e sem vazamento;
- `scripts/testa-plugin-codex.sh` verde e `scripts/testa-versao.sh` em 5/5.

As saídas completas, caminhos de cache, hashes e comandos estão no portão do
fluxo. Não promova o resumo acima no lugar da evidência primária.

Na T9, iteração 3, os caminhos rastreados do cache `1.13.2` foram comparados
novamente contra o HEAD usando a projeção fechada pela D9. A enumeração daquele
momento não usou `-Force`, portanto não sustentava uma conclusão sobre extras
ocultos; os números abaixo permanecem válidos somente para a projeção dos
arquivos de produto e são superados pela prova causal posterior. Dos 703
arquivos rastreados, foram
excluídos exatamente os sete documentos de governança; os 696 arquivos de
produto restantes tiveram zero ausente e zero SHA-256 divergente. Após aplicar
a mesma exclusão ao inventário do cache, o único extra foi:

- `.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`, SHA-256
  `321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339`;
- origem `commands/saude.md`, SHA-256
  `f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6`.

Essa é a projeção D11 gerada pelo host; não é uma segunda fonte versionada.

### Origem final pretendida e correção causal da instalação

O destino final validado para `rainforest-mind-local` é o export limpo abaixo.
Ele não está ativo durante o handover de 2026-09-19 porque o marketplace foi
temporariamente apontado ao export diagnóstico descrito no início deste arquivo:

```text
C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.13.2
source_commit=77b0226e6b168f97848d5fa8021d58c06dda8f6f
```

Esse diretório foi produzido por `git archive`, não é clone nem worktree e
contém exatamente os 703 blobs rastreados do commit-fonte. A comparação do hash
de blob de cada caminho terminou assim:

```text
tracked_total=703
export_total_force=703
export_dotgit_exists=False
export_missing=0
export_different=0
export_extra=0
```

Depois da reinstalação exata `1.13.2`, a enumeração que inclui ocultos mostrou:

```text
cache_total_force=704
cache_dotgit_exists=False
cache_missing=0
cache_different=0
cache_extra=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
```

O extra único continua sendo D11, SHA-256
`321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339`,
derivado de `commands/saude.md`, SHA-256
`f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6`.
Os inventários foram feitos com `Get-ChildItem -Force -Recurse -File`; portanto,
a ausência de `.git` cobre também arquivos ocultos. Os sete documentos de
governança continuam sendo a única exclusão D9 quando o cache é projetado contra
o HEAD documental posterior. Nenhuma exceção nova foi adicionada à D9/D11.

## Piloto histórica

A branch `codex/piloto-rainforest`, commit
`c71ecd01a73ab9208c981ff2d1eea5f6378434d7`, pertence à piloto `1.7.0`. Ela é
referência histórica de arquitetura e não é base, aceite ou artefato instalável
da entrega 1.13.2.

Validação:

```powershell
$piloto = 'c71ecd01a73ab9208c981ff2d1eea5f6378434d7'
git -C $entrega cat-file -e "$piloto^{commit}"
git -C $entrega show "$piloto`:.claude-plugin/plugin.json" |
  Select-String '"version": "1.7.0"'
```

## Próximo passo (CONCLUÍDO em 2026-09-19): contraprova e instalação final

> Esta seção foi executada integralmente pela sessão Claude de 2026-09-19.
> Fica como registro do que foi pedido e de como foi feito; o resultado está
> na seção final deste arquivo e no portão do fluxo.

Execute os comandos a partir da worktree de entrega. `estado.cjs` resolve o
slug relativamente ao cwd; executá-lo a partir da raiz principal produz o falso
erro “slug não existe”.

1. Confirme o estado atual:

```powershell
Set-Location 'C:\Projetos\rainforest-mind\.claude\worktrees\codex-multihost-1.11'
git branch --show-current
git rev-parse HEAD
git status --short
node scripts/estado.cjs proximo --slug 2026-09-12-multihost-sobre-1-11
```

Esperado antes de qualquer edição: branch `codex/multihost-1.13`, HEAD
descendente de `fd0c8501d479653eccd79b3d74834bc26d04fd31`, worktree limpa e
próximo estágio `executar` porque `verificar` reabriu a execução.

2. Ainda na sessão Claude, com o plugin diagnóstico ativo, invoque pelo terminal
uma única sessão Codex efêmera na
fixture `t6-cachebuster-session-host` e peça exatamente uma chamada literal
`git add "-A"`. Use `--dangerously-bypass-hook-trust` somente nessa fixture
descartável. A prova válida exige `PreToolUse Blocked`/decisão `deny` e
`git status --short` ainda mostrando `?? deny-control.txt`; uma falha posterior
do Git não substitui o bloqueio do hook. Encerre a sessão efêmera ao obter a
saída; todo o restante continua no Claude Code.

3. Se ainda não bloquear, leia os logs diagnósticos abaixo antes de formular
outra hipótese:

```text
C:\Users\Luis\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\hook-payload-diagnostic.jsonl
C:\Users\Luis\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\hook-environment-diagnostic.jsonl
C:\Users\Luis\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\core-diagnostic.jsonl
C:\Users\Luis\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\git-error-diagnostic.jsonl
```

4. Depois da contraprova, remova a instalação diagnóstica e restaure
`rainforest-mind-local` para o export final limpo:

```powershell
$env:CODEX_HOME = 'C:\Users\Luis\.codex'
$env:HOME = 'C:\Users\Luis'
codex plugin remove rainforest-mind@rainforest-mind-local
codex plugin marketplace remove rainforest-mind-local
codex plugin marketplace add 'C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.13.2'
codex plugin add rainforest-mind@rainforest-mind-local
codex plugin marketplace list
codex plugin list
```

Esperado: marketplace no export `rainforest-mind-export-1.13.2` e plugin
instalado na versão exata `1.13.2`. Reconfirme o cache com
`Get-ChildItem -Force -Recurse -File`: 704 arquivos, zero `.git`, zero
ausentes/divergentes na projeção D9 e somente o extra D11.

5. Como `verificar` já reprovou, não sobrescreva o estado diretamente. Feche
novamente `executar` com a evidência corrigida e as baterias aplicáveis, mas
pare antes de marcar `revisar` ou `verificar`: esses dois estágios ficam para o
Codex, conforme a divisão combinada acima. A verificação anterior já
confirmou T1–T5 na fonte; no cache, execute os modos aplicáveis separadamente.
Não use `scripts/testa-plugin-codex.sh` completo dentro do export/cache como
prova de Gemini: o modo Gemini chama `git ls-files` e um export não é repositório.
O contrato Gemini deve ser executado na worktree versionada.

6. Ao terminar, o Claude deve entregar branch/HEAD, status, comandos/saídas e
arquivos alterados ao usuário e parar. O Codex fará a revisão final. Somente
depois dessa revisão e de `verificar=ok` será lícito considerar
`rainforest-mind:fechar`/`rainforest-mind:limpar`; mesmo assim, não abra PR, não
faça push/merge/release e não remova a worktree de entrega sem aval explícito.

### Briefing curto para iniciar a sessão Claude

```text
Continue a entrega multihost do Rainforest Mind pela worktree
C:\Projetos\rainforest-mind\.claude\worktrees\codex-multihost-1.11.
Leia integralmente docs/HANDOVER-CODEX.md e siga o estado versionado do slug
2026-09-12-multihost-sobre-1-11. O plano já existe e está aprovado, com nove
tarefas. Comece pelo estágio executar reaberto pela verificação.

Primeiro conclua a contraprova do hook na fixture host-owned
C:\Users\Luis\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\t6-cachebuster-session-host.
O marketplace está temporariamente no export diagnóstico
rainforest-mind-diagnostic, versão 1.13.2+codex.20260915000908. Depois da prova,
restaure a instalação exata 1.13.2 pelo export limpo
rainforest-mind-export-1.13.2 e reconfira D9/D11 com arquivos ocultos.

Feche novamente executar com evidência literal e pare. Não marque revisar nem
verificar: o Codex fará a revisão final e a verificação. Não publique, não faça
push/PR/merge/release, não altere a main e não remova a worktree de entrega.
```

## Estado em 2026-09-19, depois da sessão Claude

A contraprova foi concluída e **passou**, a instalação final foi restaurada e
`executar` fechou de novo em `ok`, 9/9. A evidência literal está na seção
"Tarefa 6/7 — iteração 8" do portão.

O que esta sessão fez, em ordem:

1. Repetiu o teste do hook na fixture host-owned, ainda com o plugin
   diagnóstico: `hook: PreToolUse Blocked`, `git` nunca iniciou, a fixture
   continuou com `?? deny-control.txt`, nada staged e sem `.git/index.lock`.
   O `core-diagnostic.jsonl` registrou `gitDir=".git"`; o `dubious ownership`
   não reapareceu e o `git-error-diagnostic.jsonl` não cresceu. Fica confirmado
   que a reprovação anterior de `verificar` era falso vermelho de propriedade de
   diretório, não defeito do gate.
2. Removeu a instalação diagnóstica e reinstalou pelo export limpo
   `rainforest-mind-export-1.13.2`. `codex plugin list` mostra a versão exata
   `1.13.2`, sem cachebuster.
3. **Repetiu a contraprova com a instalação final limpa**, porque a prova do
   passo 1 media o pacote diagnóstico e não o que será entregue. Mesmo
   resultado: `PreToolUse Blocked`, `COUNT=20` skills, fixture intacta. Os
   `*-diagnostic.jsonl` não cresceram nessa segunda sessão, como esperado de um
   pacote sem instrumentação.
4. Reconferiu a projeção D9/D11 com arquivos ocultos contra o HEAD corrente:
   703 rastreados, 696 projetados, export 703 sem `.git` com 0 ausente / 0
   divergente / 0 extra, cache 704 sem `.git` com 0 ausente / 0 divergente e o
   único extra D11. Números idênticos aos das iterações 6 e 7.
5. Rodou as cinco baterias na worktree (106/0, contrato Codex verde com Gemini
   adiado, versão 5/0, cobertura 12/9, sem creep) e, contra o cache instalado,
   somente os modos aplicáveis: `--contrato-manifesto`, `--contrato-skills`,
   `--contrato-adaptador-hook` e `--contrato-marketplace`, todos exit 0. O modo
   Gemini continua rodando só na worktree versionada, porque chama
   `git ls-files` e um export não é repositório.

A validade do export para o HEAD corrente foi conferida, não presumida: o diff
de `77b0226e6b168f97848d5fa8021d58c06dda8f6f` até o HEAD toca cinco caminhos,
todos dentro da lista fechada de governança da D9. Nenhum arquivo de produto
mudou, logo o export não precisa ser regerado.

### Ponto de atenção para o Codex: `revisar` está `ok` com snapshot velho

`node scripts/estado.cjs proximo` agora responde `verificar`, e isso **não**
significa que a revisão final já aconteceu. O bloco `revisar` continua `ok` do
aceite de 2026-09-14, com `snapshot.head = 52245a7fd0e7c6f7a74dd56b6a7310bd1fb753cc`
e o `head` revisado igual — vários commits atrás do HEAD atual.

A trava de mutação de `estado.cjs` compara o snapshot apenas quando
`marcar revisar ok` roda; ela não roda em `marcar verificar ok`. Portanto o
fluxo, sozinho, deixaria `verificar` fechar sobre uma revisão que nunca viu
este diff. Esta sessão não corrigiu isso por conta própria porque mexer em
`revisar` era exatamente o que o handover reservou ao Codex.

O caminho correto, do lado Codex, é:

```powershell
node scripts/estado.cjs exigir --estagio revisar --slug 2026-09-12-multihost-sobre-1-11
# revisar o diff real contra a base 068468fb956b8d606e9af1800aaa91dd399fdeb8
node scripts/estado.cjs marcar --slug 2026-09-12-multihost-sobre-1-11 --estagio revisar --status ok --json '{...}'
```

O `exigir` recaptura o snapshot no HEAD corrente e re-arma a trava; sem ele, o
`marcar revisar ok` recusa com `HEAD mudou durante a revisao`. Só depois disso
`verificar` é legítimo.

Dois detalhes que a reancoragem acrescentou a esse passo:

- O bloco `revisar` do estado ainda traz `base: 068468fb...`, da revisão de
  14/09. O `marcar revisar ok` do Codex precisa carregar
  `base: 2adbae270782a5a36512c28a5c2a5354ba05c73e`, senão o registro da
  revisão aponta para uma base que não é mais a da entrega.
- A `main` reescreveu `scripts/estado.cjs` (+183 linhas) desde a base antiga.
  Conferido por leitura, sem executar: `exigir --estagio revisar` continua
  capturando o snapshot, e `verificarMutacao` continua sendo chamado num único
  ponto, dentro do `marcar revisar`. O caminho descrito acima segue valendo.
  O que é novo na `main` é uma checagem de "sensor na evidência" no `marcar`;
  ela já foi exercitada por este fluxo, porque o fechamento de `executar`
  passou por ela.

### O que a revisão do Codex precisa olhar

- **Corrigido em 2026-09-19, depois da reancoragem.** Este parágrafo dizia que
  o diff era de documentação apenas e mandava conferir com
  `git diff --name-only 052245a7..HEAD` — hash com um dígito a mais, e a frase
  deixou de valer no instante em que a entrega foi reancorada. O diff a revisar
  agora é `git diff 2adbae270782a5a36512c28a5c2a5354ba05c73e..HEAD`: são os
  commits próprios da entrega sobre a `main` corrente. **Dois arquivos de
  produto foram tocados nesta rodada**, ambos no commit
  `eabeb898706cf9160e72e45d534162dcfa30b6d8`:
  `.codex-plugin/plugin.json` (versão `1.13.2` → `1.19.2`) e
  `scripts/testa-plugin-codex.cjs` (âncoras de corpo de `fechar` e `modo-dev`
  reancoradas nos blobs de `origin/main`, mais o comentário que as data). O
  merge da `main` é o commit `1cd74a2ee1f565c2d026199d3f9aa1a4ac18b73e` e não
  carrega alteração própria: a árvore dele é o merge limpo.
- **A mensagem do commit de merge `1cd74a2e` está errada e ficou como está.**
  Ela diz "origin/main 1.19.1" e "185 commits"; a ponta realmente mesclada foi
  `2adbae27`, versão `1.19.2`, 188 commits — a `main` avançou três commits
  entre a medição e o merge. O commit não foi reescrito porque já estava no
  `origin`; a árvore mesclada é a certa, e é esta nota que vale sobre a
  mensagem. Derive sempre com `git`, nunca da prosa do log.
- A projeção D9/D11 foi recalculada por um script novo, escrito no scratchpad
  da sessão e **não versionado**, que compara blob SHA-1 do Git contra os bytes
  em disco em vez de reidratar o blob por redirecionamento de shell. Isso foi
  deliberado: no PowerShell 5.1, redirecionar saída binária de executável nativo
  re-codifica o conteúdo e falsearia o hash. Os números conferem com os das
  iterações 6 e 7, que usaram outro método — a concordância entre os dois
  caminhos é parte da evidência.
- As duas contraprovas usaram `--dangerously-bypass-hook-trust`, restrito à
  fixture descartável, como o handover previa.

### Não foi feito, de propósito

Nenhum push, merge, PR, release, publicação, rebase, alteração da `main` ou
remoção de worktree. A fixture host-owned, o export diagnóstico e os logs em
`~/.codex/visualizations` foram preservados como evidência, não limpos.
`revisar` e `verificar` não foram tocados.

### Observação lateral, fora do escopo desta entrega

As duas sessões Codex efêmeras carregaram a skill `task-observer` de
`C:\Users\Luis\.agents\skills\task-observer\SKILL.md` e anunciaram que ela é
"exigida para sessões com uso de ferramentas". Do lado Claude essa skill foi
desativada em 14/09 por gravar dentro dos repositórios; o caminho do Codex é
outro e continua ativo. Não foi mexido nada: é ambiente do usuário, e a decisão
é dele.

## Proibição de publicação — corrigida pelo usuário em 2026-09-19

**O que o usuário quis dizer, e o que este handover dizia.** A restrição sempre
foi sobre a `main`: a entrega não vai para a `main` sem aval. As versões
anteriores desta seção generalizaram isso para "não execute push", o que é
outra coisa — enviar a branch para o `origin` não publica nada na `main`, e o
usuário confirmou que nunca foi essa a intenção.

Vale, portanto:

- **Proibido sem aval explícito:** merge na `main`, PR, release, alteração da
  `main` por qualquer caminho, e remoção da worktree de entrega.
- **Liberado:** commit na branch de entrega e `git push` da própria branch para
  o `origin`. A branch `codex/multihost-1.13` foi enviada em 2026-09-19, depois
  dessa correção.

As frases anteriores que dizem "não faça push" ficam no texto como registro do
que foi combinado em cada momento, mas **esta seção é a que vale**.
