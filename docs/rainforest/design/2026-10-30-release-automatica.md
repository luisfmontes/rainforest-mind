# Release no GitHub a cada versão nova, sem depender da sessão

## Objetivo
O GitHub tinha uma única release, a `v1.0.0` de 2026-09-03. Todas as versões seguintes, até a 2.2.1, saíram só como bump do `plugin.json`, do badge e do CHANGELOG, sem tag. O Claude Code instala pela versão do manifesto, então quem usa pelo `/plugin` recebia a versão nova. Quem olha o repositório via "Latest: 1.0.0" e um README dizendo outra coisa. O usuário notou em 2026-10-30. A `v2.2.2` foi publicada à mão no mesmo dia, com as notas de 2.0.0 até 2.2.2. Este trabalho faz toda versão nova que chega à `main` ganhar tag e release sozinha, com as notas tiradas da seção dela no CHANGELOG.

Conduzido pela sessão em 2026-10-30, sob a autorização permanente de seguir o fluxo com a recomendada. O usuário escolheu a opção "release de recuperação agora, e automática daqui em diante". As decisões ficam marcadas no PR para veto.

## Decisões fechadas
- **D1 — Quem publica é um workflow do GitHub Actions, `.github/workflows/release.yml`, no push à `main` que toca `.claude-plugin/plugin.json`, mais `workflow_dispatch`.** Porquê: o PR de bump pode ser mergeado pelo `fechar`, por outra sessão, pelo Codex ou pela interface web, e só o push à `main` passa por todos esses caminhos. Um passo no `fechar` dependeria de a sessão lembrar, e foi esse esquecimento que deixou a lacuna de 1.0.0 a 2.2.1. O `workflow_dispatch` serve para repetir à mão se o run falhar.
- **D2 — A lógica mora em `scripts/release-da-versao.cjs`, e o workflow só o chama.**
  - O script lê a versão de `.claude-plugin/plugin.json`.
  - Se a release `v<versão>` já existe (`gh release view`), sai 0 dizendo que já existe.
  - Senão, extrai do `CHANGELOG.md` a seção `## <versão> — ...` até o próximo `## ` e roda `gh release create v<versão> --target <sha> --title "rainforest-mind <versão>" --notes-file <arquivo>`.
  - Seção ausente ou vazia sai 1 sem criar nada, e o run fica vermelho à vista.
  - `--seco` imprime o comando e as notas sem chamar o `create`.
  - Porquê: YAML não se testa na bateria, script sim. O `sha` vem de `--sha`, e o workflow passa `$GITHUB_SHA`.
- **D3 — Idempotência pela existência da release, não da tag.** Rodar de novo o mesmo push, ou um push à `main` que toca o `plugin.json` sem mudar a versão, não cria nada. Se a tag existe sem release, o `gh release create` a usa como está. Porquê: a release é o que falta hoje, e a tag sozinha não aparece como "Latest".
- **D4 — `ubuntu-latest`, `permissions: contents: write` só neste workflow, `GH_TOKEN` do `GITHUB_TOKEN`, sem segredo novo.** Porquê:
  - O script é node puro mais `gh`, sem nada do Windows que justifique o runner das baterias (`baterias.yml` explica por que aquele é Windows).
  - O gatilho é push à `main`, nunca PR, então um PR de fork não chega a rodar o `create`.
  - O repositório é público, e o minuto de Actions não é cobrado.
- **D5 — Bateria `scripts/testa-release-da-versao.sh` com stub de `gh`.** Ela monta um repositório falso com `plugin.json` e `CHANGELOG.md` e cobre quatro casos:
  - (a) Release inexistente: o stub registra um `release create` com `v<versão>`, o título, o `--target` e as notas iguais à seção.
  - (b) Release existente: nenhum `create`.
  - (c) Seção ausente: exit 1 e nenhum `create`.
  - (d) As notas param antes da seção seguinte, sem vazar a versão anterior.

  A mutação que reverte o comportamento real é tirar a checagem de existência, e o caso (b) fica vermelho.
- **D6 — Docs: `CONTRIBUTING.md`, na seção "Versão", e o parágrafo de release do `skills/fechar/SKILL.md` dizem que tag e release saem do `release.yml` no merge do bump.** O README, em "Instalação", aponta as notas de cada versão nas Releases do GitHub e no CHANGELOG. Porquê: o `fechar` hoje diz "release é decisão dele, e o commit de bump é entrega própria". O bump continua sendo decisão dele, mas a release deixa de ser um passo esquecível.
- **D7 — Contra quem protege, e o que fica fora.** Protege contra versão nova na `main` sem release no GitHub. Não cria releases para versões passadas: 1.x até 2.2.1 ficam sem tag, e a `v2.2.2` à mão já carrega as notas da linha 2.x. Não muda quando nem como o bump acontece.
- **D8 — Versão 2.3.0 (MINOR).** Entra coisa nova: um workflow e um script, e a release passa a ser automática (tabela do `CONTRIBUTING.md`). O próprio merge do bump 2.3.0 é o primeiro teste real do workflow.

## Avaliado e descartado
- **Passo de release no `fechar` ou no `publicar-branch.cjs confirmar-merge`.** Só cobre o merge feito pela sessão no fluxo, e depende de a sessão chegar até lá.
- **Releases retroativas, uma por versão desde a 1.0.0.** São dezenas de releases com notas que ninguém vai ler, e o usuário escolheu a outra opção.
- **Ação de terceiro de release-por-changelog.** Seria uma dependência externa com permissão de escrita no repositório, para um script de algumas dezenas de linhas.
- **Disparar por push de tag.** Exigiria alguém criar a tag, que é justamente o passo esquecido.

## Fora de escopo
- Assinar a tag, ou anexar artefato à release. O marketplace instala do repositório, não da release.
- Mudar o `conferir-versao.cjs` ou a regra de quando subir a versão.

## Varredura
docs/rainforest/varredura/2026-10-30-release-automatica.txt — nenhuma Issue nem PR sobre release no GitHub. Os PRs #72 e #129 usam "release" no sentido de bump de versão. As duas ideias casadas são de release de cliente, de outro domínio.

## Em aberto
nada
