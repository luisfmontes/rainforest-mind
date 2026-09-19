# Plano: adaptação multihost sobre o Rainforest Mind 1.13.2

Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`

Base inicial confirmada: `a338dd02ad495f87a66d84af2ab24eab3d2660b8`.
Base corrente confirmada antes da tarefa 4: `cf1ad7689f84428eb0b10943c0f1cf1a662b8faf` (`1.12.0`). Os 12 commits locais foram reaplicados sobre ela após confirmar zero caminhos sobrepostos.
Base corrente: `2adbae270782a5a36512c28a5c2a5354ba05c73e` (`1.19.2`), reancorada em 2026-09-19 por merge da
`origin/main`. A base anterior era `068468fb956b8d606e9af1800aaa91dd399fdeb8` (`1.13.2`), fixada
após a primeira T7; o rebase daquela vez descartou como já aplicado o commit do gate de staging,
cujo patch era idêntico ao incorporado upstream. A troca de âncora seguiu a análise de
sobreposição registrada no portão: a `main` não toca nenhum arquivo de produto da adaptação
Codex, e os dois `SKILL.md` que ela reescreveu só divergem da entrega no corpo, que a entrega
não altera.
Referência histórica confirmada: `codex/piloto-rainforest` em
`c71ecd01a73ab9208c981ff2d1eea5f6378434d7`.

## Fatos, inferências e lacunas

- **CONFIRMADO:** `.claude-plugin/plugin.json` declara `1.13.2`; a base não
  contém `.codex-plugin/plugin.json` nem `.agents/plugins/marketplace.json`.
- **CONFIRMADO:** há 19 `skills/*/SKILL.md`; `fechar`, `modo-dev`,
  `montar-corpus` e `regua` não satisfazem hoje o frontmatter aceito pelo Codex.
- **CONFIRMADO:** o núcleo herdado pela 1.12 permitia `git add "-A"` e
  `bash -c "git status; git add -A"`; `git add -- "-A"` permanece um pathspec
  explícito e deve continuar permitido.
- **CONFIRMADO:** a piloto 1.7 tem os arquivos novos que servem de referência,
  mas o contrato congela 18 skills e âncoras de corpos antigos.
- **CONFIRMADO:** o instalador copia metadados `.git` quando a origem é um clone
  ou worktree; um export por `git archive` do commit candidato contém somente os
  arquivos versionados e é a origem verificável da instalação final.
- **INFERIDO:** os campos adicionais de `interface` do manifesto Codex podem
  conservar os valores comprovados na piloto; os quatro metadados canônicos
  continuam vindo do manifesto Claude conforme D3.
- **CONFIRMADO:** inventários de export e cache usam
  `Get-ChildItem -Force -Recurse -File`; enumeração sem `-Force` não prova a
  ausência de metadados ocultos.

## O que não pode quebrar

- Claude continua lendo `.claude-plugin/plugin.json` e `hooks/hooks.json` sem
  carregar o adaptador Codex.
- O corpo byte a byte das quatro skills normalizadas permanece igual ao da
  base corrente; só o frontmatter pode mudar.
- `git add -- "-A"` continua permitido, enquanto opções reais de staging total
  continuam recusadas mesmo citadas ou dentro de wrappers.
- O inventário do contrato vem do disco e valida todas as skills presentes;
  nenhuma constante fixa 19.
- O cachebuster nunca entra no commit final, cuja versão é exatamente `1.13.2`.
- Todo arquivo rastreado fora da lista fechada de sete documentos de governança
  da D9 aparece byte a byte no cache; extras são recusados, exceto a projeção
  Codex fechada de `commands/saude.md` definida em D11.
- A instalação final nasce de um export limpo do commit candidato, nunca de um
  checkout Git; export e cache são inventariados com `-Force` e não contêm
  arquivo ou diretório `.git`.
- Nenhum manifesto, hook ou payload Gemini é criado nesta entrega.
- Nenhum push, merge, PR, release ou alteração na `main` ocorre sem aval
  explícito do usuário.
- Baterias que mutam fonte de produção rodam sequencialmente e restauram os
  bytes originais, mesmo quando falham.

## Tarefas

### 1. Corrigir no núcleo a semântica de staging total [tipo: implementar]
atende: D1, D6, D10
arquivos: `hooks/gate-staging-total.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `const resto = toksComAspas.slice(pos + 1).map((t) => t.v);`
  para: `const resto = toksComAspas.slice(pos + 1).filter((t) => !t.q).map((t) => t.v);`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: `testa-gate-staging-total.sh`, casos `git add "-A"`, `git "add" -A` e `bash -c "git status; git add -A"`
pronto quando: com payload real `PreToolUse` cujo `tool_input.command` é
`git add "-A"`, `git "add" -A` ou
`bash -c "git status; git add -A"`, o núcleo sai 2 e explica a opção real;
com `git add -- "-A"`, `git add -- "-u"` e mensagens de commit contendo
`-a`/`--all`, sai 0 — provado por `bash hooks/testa-gate-staging-total.sh`
nomeando cada entrada e terminando em zero falhas.

### 2. Criar o contrato estrutural Codex sobre o inventário corrente [tipo: implementar]
atende: D2, D3, D10
arquivos: `.codex-plugin/plugin.json`, `scripts/testa-plugin-codex.cjs`, `scripts/testa-plugin-codex.sh`, `skills/fechar/SKILL.md`, `skills/modo-dev/SKILL.md`, `skills/montar-corpus/SKILL.md`, `skills/regua/SKILL.md`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/montar-corpus/SKILL.md`
  de: `description: "Constrói acervo em markdown a partir de um corpus de wiki em versão de controle."`
  para: `description:`
  bateria: `node scripts/testa-plugin-codex.cjs --contrato-skills`
  fixture: modo `--contrato-skills`, caso que diagnostica `montar-corpus (description ausente)`
pronto quando: com a lista real de diretórios que contêm
`skills/*/SKILL.md`, o contrato descobre e valida todos os 19 nomes sem comparar
contra número fixo; o manifesto Codex resolve `./skills/` e iguala ao manifesto
Claude `name`, `version`, `description` e `author`; e o SHA-256 do corpo das
quatro skills antes/depois da normalização é idêntico ao da base inicial e permaneceu inalterado na base 1.12 — provado
por `node scripts/testa-plugin-codex.cjs --contrato-manifesto` imprimindo a
quantidade descoberta e as quatro âncoras de corpo, sem falhas.

### 3. Adaptar o protocolo do hook sem duplicar a política [tipo: implementar]
atende: D1, D6, D10
arquivos: `hooks/codex-gate-staging-total.cjs`, `hooks/codex-gate-staging-total.json`, `scripts/testa-plugin-codex.cjs`, `scripts/testa-plugin-codex.sh`, `.codex-plugin/plugin.json`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/codex-gate-staging-total.json`
  de: `node "${PLUGIN_ROOT}/hooks/codex-gate-staging-total.cjs"`
  para: `node "${PLUGIN_ROOT}/hooks/gate-staging-total.cjs"`
  bateria: `node scripts/testa-plugin-codex.cjs --contrato-adaptador-hook`
  fixture: modo `--contrato-adaptador-hook`, caso `handler Codex -> core direto`
pronto quando: com payload Codex real de `PreToolUse/Bash`, o registro seletivo
chama exatamente um adaptador fino; uma recusa do núcleo vira JSON oficial com
`permissionDecision: "deny"` e o mesmo motivo, uma permissão não imprime decisão,
e JSON malformado ou falha inesperada vira deny seguro sem ecoar o payload —
provado por `bash scripts/testa-plugin-codex.sh`, incluindo os marcadores de
allow, deny, falha interna e entrada malformada.

### 4. Fazer o portão global comparar os dois manifestos [tipo: teste]
atende: D3, D7
arquivos: `scripts/testa-versao.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `.codex-plugin/plugin.json`
  de: `"version": "1.13.2"`
  para: `"version": "1.13.3"`
  bateria: `bash scripts/testa-versao.sh`
  fixture: seção `manifesto Codex na mesma versao da fonte Claude`, esperando divergência `1.13.3` versus `1.13.2`
pronto quando: com Claude e Codex em `1.13.2`, o portão informa igualdade;
mudando somente o manifesto Codex para `1.13.3`, ele sai não zero e mostra os
dois valores — provado por `bash scripts/testa-versao.sh` no original e por
`node scripts/conferir-mutacao.cjs --arquivo .codex-plugin/plugin.json --de '"version": "1.13.2"' --para '"version": "1.13.3"' --bateria 'bash scripts/testa-versao.sh'`.

### 5. Distribuir a raiz única e manter Gemini como escopo negativo [tipo: configurar]
atende: D4, D8, D10
arquivos: `.agents/plugins/marketplace.json`, `scripts/testa-plugin-codex.cjs`, `scripts/testa-plugin-codex.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `.agents/plugins/marketplace.json`
  de: `"path": "./"`
  para: `"path": "./codex"`
  bateria: `node scripts/testa-plugin-codex.cjs --contrato-marketplace`
  fixture: modo `--contrato-marketplace`, caso `source.path nao resolve o manifesto deste repo`
pronto quando: com a entrada `rainforest-mind` do marketplace local, resolver
`source.path` chega à mesma raiz que contém os manifestos Claude e Codex; e a
lista rastreada pelo Git não contém manifesto, hook, adaptador ou fixture de
payload Gemini fora dos documentos deste fluxo — provado por
`node scripts/testa-plugin-codex.cjs --contrato-marketplace` e
`node scripts/testa-plugin-codex.cjs --contrato-gemini`, ambos nomeando o efeito
verificado.

### 6. Provar uma iteração local com cachebuster [tipo: configurar]
atende: D5, D9
arquivos: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`
depende de: 4, 5
paralela: nao
mutacao: n/a
  motivo: tarefa operacional sobre o instalador e seu cache externo; a falsificação é comparar a versão/bytes realmente instalados, não inverter fonte persistente.
pronto quando: com os manifestos temporariamente em
`1.13.2+codex.<token>` e o marketplace apontando para este worktree, reinstalar
o plugin cria uma entrada de cache nessa versão, uma sessão nova enumera as
skills descobertas e o hook recusa `git add "-A"`; em seguida os dois manifestos
voltam byte a byte a `1.13.2` — provado no portão por comandos, saídas, caminho
do cache e hashes antes/depois, sem registrar o cachebuster no diff final.

### 7. Reinstalar exatamente 1.13.2 e executar o contrato ponta a ponta [tipo: teste]
atende: D1, D2, D3, D6, D8, D9, D11, D12
arquivos: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`
depende de: 6
paralela: nao
mutacao: n/a
  motivo: validação do artefato instalado fora do repositório; as mutações dos comportamentos persistentes já pertencem às tarefas 1 a 5.
pronto quando: com o marketplace local apontando para um export limpo produzido
por `git archive` do commit candidato, sem arquivo ou diretório `.git`, e ambos
os manifestos exatamente em `1.13.2`, uma reinstalação produz cache
`1.13.2` em que todos os arquivos rastreados fora da lista fechada de
governança da D9, inclusive `.codex-plugin/plugin.json`, existem com SHA-256
idêntico; nenhum extra é aceito
fora de `.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`,
projeção de `commands/saude.md` gerada pelo host e registrada com hash. O export
e o cache são enumerados por `Get-ChildItem -Force -Recurse -File`, e a prova
recusa qualquer `.git`, inclusive oculto; numa sessão Codex nova, uma skill
é invocável, `git status` e `git add -- "-A"` são permitidos, `git add "-A"` e
`bash -c "git status; git add -A"` são negados, e JSON malformado falha fechado
sem vazamento — evidências completas coladas no portão com zero caso pulado.

### 8. Atualizar o rastro corrente e o handover sem promover a piloto [tipo: docs]
atende: D4, D5, D9, D10, D11
arquivos: `docs/HANDOVER-CODEX.md`, `docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md`, `docs/rainforest/mapas/COBERTURA.md`, `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`
depende de: 7
paralela: nao
mutacao: n/a
  motivo: documentação de continuidade; a falsificação é a coerência dos hashes, versão, escopo e comandos com os artefatos medidos nas tarefas anteriores.
pronto quando: uma pessoa retomando apenas por `docs/HANDOVER-CODEX.md` vê a
branch/worktree/HEAD rederivável, sabe que `c71ecd01...` é referência histórica
1.7, encontra design/plano/portão do fluxo iniciado na 1.11 e entregue na 1.13.2, enxerga Gemini como adiado e
a proibição explícita de publicar/mesclar na main sem aval; cada hash e caminho
do texto é resolvido por `git rev-parse`, `git cat-file -e` ou `Test-Path`, e os
números do portão coincidem com as saídas registradas.

### 9. Fechar a execução local com todas as travas, sem publicar [tipo: teste]
atende: D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12
arquivos: `docs/HANDOVER-CODEX.md`, `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`, `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`
depende de: 8
paralela: nao
mutacao: n/a
  motivo: tarefa de integração e registro; não introduz comportamento novo, apenas reexecuta os contratos e registra seus resultados.
pronto quando: com o commit candidato local, `bash hooks/testa-gate-staging-total.sh`,
`bash scripts/testa-plugin-codex.sh`, `bash scripts/testa-versao.sh`,
`node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11`
e `node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 2adbae270782a5a36512c28a5c2a5354ba05c73e --head HEAD`
terminam verdes; a projeção do cache `1.13.2` contra o HEAD, excluindo somente
os sete documentos de governança da D9, tem zero caminho ausente e zero SHA-256
divergente, e o único extra continua sendo o derivado autorizado pela D11. O
marketplace ativo aponta para o export limpo do commit candidato; a enumeração
com `Get-ChildItem -Force -Recurse -File` confirma zero `.git` no export e no
cache, sem omitir arquivos ocultos; o
handover registra execução `9/9` e aponta `revisar` como próximo estágio;
`git diff --name-only 068468fb...HEAD` contém somente os
caminhos autorizados pelo plano; o estado registra a evidência por tarefa; e
`git branch --show-current`, `git status --short` e a ausência de comandos de
push/merge/release no portão demonstram que a entrega permanece somente na
branch `codex/multihost-1.13`, aguardando aval do usuário para qualquer
publicação na main.

## Ordem de execução

As nove tarefas são deliberadamente seriais. T1–T5 compartilham baterias e
fontes mutados; T6–T7 alteram a instalação local; T8 só pode registrar hashes e
saídas reais depois da instalação final; T9 integra o conjunto. Não há grupo
`paralela: sim` seguro nesta fatia.

## Premissas aceitas sem conferir

- Nenhuma decisão de produto ficou aberta: D1–D12 estão formalmente aprovadas
  no estado do fluxo.
- A instalação local do Codex continuará oferecendo o mesmo comando de
  reinstalação usado na piloto; a tarefa 6 deve parar e registrar a divergência
  se a interface instalada tiver mudado.
