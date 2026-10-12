# Uma pasta só de configuração do Claude Code

## Objetivo

O Luís abre o Claude Code com um comando só, sem escolher conta nem pasta. Tudo mora em `~/.claude`; o vigia da troca
de conta (1.62.0, `docs/rainforest/design/2026-10-10-troca-de-conta.md`) troca o login dentro dessa pasta única pelo
uso. A `~/.claude-personal` é absorvida e aposentada sem perder memória, histórico, plugin nem servidor MCP.

## Decisões fechadas

- **D1 — Fica a `~/.claude`; a `~/.claude-personal` é absorvida nela** — porquê: é a pasta padrão de toda ferramenta
  que abre sem `CLAUDE_CONFIG_DIR` (extensão do VS Code, app desktop, `claude` puro); já guarda os hooks, scripts e
  statusline de que o `settings.json` da pessoal depende por caminho absoluto; tem 26 skills contra 4 (as 4 também
  estão nela), `protheus` 2.27.6 e `mit-docs` 1.4.0 contra 2.19.0 e 1.3.3, e ~3,4× o `history.jsonl` (medido em
  2026-10-12). O `CLAUDE.md` das duas é idêntico (mesmo md5).
- **D2 — Migra tudo que é do Luís, e nada se sobrescreve** — porquê: "não perder nada" é a condição para aposentar.
  - `projects/<projeto>/` — transcritos (`*.jsonl`, nomes por UUID) copiados para o mesmo projeto em `~/.claude`;
    arquivo de mesmo nome e conteúdo diferente não é sobrescrito: vira `<nome>.pessoal.<ext>` e entra no relatório.
  - `projects/<projeto>/memory/` — memórias unidas por projeto pela mesma regra; o `MEMORY.md` de destino ganha, ao
    fim, as linhas do índice pessoal que apontam para arquivo que não estava lá (medido: 11 projetos com `memory/`
    nas duas, no máximo 2 nomes coincidentes, no `rainforest-mind`).
  - `history.jsonl` — linhas da pessoal acrescentadas, sem repetir linha idêntica.
  - `file-history/`, `todos`/`tasks`, `plans` e afins que existirem — copiados sem sobrescrever.
  - `.claude.json` da pessoal → `~/.claude.json`: `mcpServers` por união de nome (medido: `whatsapp`, `gmail`,
    `playwright` idênticos; `github` só na pessoal; `protheus` só na de trabalho — sem conflito); `projects` por
    união de caminho, sem sobrescrever entrada existente. Nome de MCP igual com definição diferente para a migração
    com exit ≠ 0 antes de escrever.
  - Plugins: o que só a pessoal tem instalado e habilitado (`security-guidance`) é instalado e habilitado em
    `~/.claude` pelo próprio CLI (`claude plugin install`), nunca copiando o cache.
  - Credenciais: a `claudeAiOauth` da pessoal **não** se copia (refresh token de uso único — D2 do design de
    2026-10-10): ela entra como reserva/estacionado da conta `pessoal` em `~/.rainforest/contas`, pelo mesmo
    mecanismo de mover que o vigia usa.
  - Fica de fora o que é cache ou estado de máquina: `cache/`, `daemon*`, `session-env/`, `sessions/`,
    `shell-snapshots/`, `telemetry/`, `debug/`, `statsig/`, `stats-cache.json`, `plugins/` (reinstalado pelo CLI).
- **D3 — A pessoal é renomeada para `.claude-personal.aposentada`, nunca apagada pela migração** — porquê: rollback é
  renomear de volta e refazer o login nela (`/login` com `CLAUDE_CONFIG_DIR` na pasta), porque a credencial sai da
  pasta na migração para não ficar em dois arquivos (emenda da revisão, 2026-10-12); apagar é decisão posterior e
  explícita do Luís.
- **D4 — Com uma pasta, a conta da casa é a team: a pasta passa para a max quando a team passa de 97% (5 h ou
  semana) e a max está abaixo de 60%/85%, e volta para a team quando o limite que travou zerar** — porquê: o
  trabalho da TOTVS fica a maior parte do tempo sob a conta da organização e a max é o transbordo. Custo aceito:
  projeto pessoal roda na team quando ela tem folga, e trabalho TOTVS roda na max no transbordo (já aceito no D1 de
  2026-10-10). Guarda de vida (D11 de 2026-10-10), renovação de reserva (D13) e troca manual (`/conta pessoal|trabalho`,
  sem volta automática — D8) seguem iguais; só deixa de existir a "outra pasta".
- **D5 — Um comando só: `claude-pessoal` e `claude-trabalho` saem do `$PROFILE` e entra um único `claude` que atualiza
  os plugins e abre sem `CLAUDE_CONFIG_DIR`** — porquê: é o "não escolher" pedido; a atualização de plugins
  (marketplace antes de plugin) continua valendo para a pasta única. O `$PROFILE` é ambiente do Luís: a migração
  mostra a mudança e só a grava com `--aplicar`. Emenda (executar, 2026-10-12): o perfil só é tocado com
  `--profile <arquivo>` explícito (o README manda `--profile $PROFILE`); sem a flag, nada no perfil muda — o
  padrão de resolver o `$PROFILE` sozinho foi descartado por gravar fora do pedido explícito.
- **D6 — O plugin funciona nos dois modos e detecta sozinho: existe `~/.claude-personal` → modo duas pastas, como na 1.62.0; não existe → modo uma pasta** — porquê: o repo é
  público e outros usuários podem manter o par. O que hoje supõe exatamente duas pastas (`scripts/conta.cjs:39-61` e
  `:733`, `scripts/lib/conta-decidir.cjs:6` e `:47`, `hooks/lib/contas-claude.cjs:44` e `:84-86`) passa a ler a lista
  de pastas existentes. A pasta aposentada (`.claude-personal.aposentada`) não conta como pasta.
- **D7 — A migração é um script (`scripts/conta.cjs unificar`), disparado pelo Luís com todas as janelas do Claude
  fechadas; sem `--aplicar` só relata o que faria** — porquê: copiar transcrito com sessão gravando nele corrompe a
  cópia. O script recusa (exit 2) se houver processo `claude` vivo ou sessão viva no `sessoes.json`, desagenda o
  vigia antes de mexer e o reagenda apontando para o clone de `~/.claude` depois, e imprime um relatório: quanto
  copiou por classe, cada conflito renomeado, cada linha de índice acrescentada.

## Avaliado e descartado

- **Escolher a pasta pela pasta de trabalho (`C:\Microsiga\...` → trabalho)** — o Luís escolheu "uma pasta só"; manter
  duas pastas mantém a memória dividida (os mesmos projetos já têm histórico nas duas).
- **Ficar com a `~/.claude-personal`** — exigiria `CLAUDE_CONFIG_DIR` em todo lugar que abre o Claude Code (VS Code,
  desktop) e mover hooks/scripts/statusline de que ela já depende na outra pasta.
- **Copiar `plugins/` da pessoal** — o cache é indexado por versão e o registro de instalação aponta caminhos; o CLI
  reinstala o que falta.

## Fora de escopo

- Apagar a `.claude-personal.aposentada` — decisão posterior do Luís.
- Unificar `~/.codex` ou qualquer outra ferramenta.
- Mudar limiares, guarda de vida ou renovação da troca de conta.

## Varredura

`docs/rainforest/varredura/2026-10-12-pasta-unica.txt`: nenhum trabalho anterior de unificação. A ideia
`busca-de-sessao-esqueceu-o-config-dir-pessoal` perde a razão de existir no modo uma pasta (D6) — colher ao fechar.

## Em aberto

Nada.
