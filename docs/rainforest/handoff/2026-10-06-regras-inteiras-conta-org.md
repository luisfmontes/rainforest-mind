# Handoff — regras inteiras na conta de trabalho (org) via session.append

Sessão de origem: bd14331a (conta de trabalho `~/.claude`), 2026-10-06, CLI 2.1.292.
Destino: brainstorm na conta pessoal, neste worktree (`worktree-regras-inteiras-conta-org`, base `a85f9315`).
Ideia de origem: `regras-inteiras-barradas-pelo-sec-default-na-conta-org` (em `~/.rainforest/ideias.jsonl`).

## O problema, medido

O mod da abertura (`hooks/register.ts`, fluxo `2026-10-02-mod-regras-inteiras`) entrega as 17
regras pelo `prompt.compose`. Na conta de trabalho isso não chega:

- Conta de trabalho (`~/.claude`, login Team/Enterprise da TOTVS): o built-in `cc-plugin-sec-default`
  carrega e ignora `prompt.compose`, `prompt.section` e `prompt.context` de todo plugin tier `user`.
  Debug: `rf-compose-spike+rainforest-mind: prompt.compose bypassed by cc-plugin-sec-default (tier user); beneath runs`.
  Sonda com 3 canários num `claude -p --model haiku`: resposta `NONE`.
- Conta pessoal (`~/.claude-personal`): sem sec-default. Os 3 canários voltam, e o debug diz
  `rainforest-mind: wrote a text of 48391 characters (prompt.compose; over 32000, accepted: a plugin's text is its own to size)`.
- Efeito: na conta de trabalho a sessão vive só com o núcleo do hook clássico SessionStart (~3 KB),
  em silêncio — o problema que o fluxo mod-regras-inteiras resolveu continua lá.

O sec-default carrega quando a máquina tem managed settings OU o login é Team/Enterprise
(doc: https://code.claude.com/docs/en/plugins/mods/admin). Esta máquina não tem managed settings
(nem arquivo em `C:\Program Files\ClaudeCode`, nem política no registro): o gatilho é o login org.

## O caminho que passa, medido

Mod tier `user` com `session.start` que chama `$.session.append` de ~31 KB com os 3 canários,
na conta de trabalho: debug `plugin.register: rf-append-spike ... judged by cc-plugin-sec-default: admitted`,
e o modelo devolveu os 3 canários. `session.append` não está na lista de eventos do sec-default.

Código da sonda (estava no scratchpad da sessão de origem, que some):

```ts
import type { Register } from 'claude-code'

const FILLER = 'Regra de teste: este paragrafo so ocupa espaco para medir o teto da linha anexada. '.repeat(19)
const bloco = (n: number) => Array.from({ length: n }, () => FILLER).join('\n')
const TEXTO = ['CANARIO-INICIO: AZUL-7341', bloco(10), 'CANARIO-MEIO: VERDE-2209', bloco(10), 'CANARIO-FIM: ROXO-5583'].join('\n')

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: TEXTO }] } })
    return r
  })
}
```

Como rodar (manifest `{ "name": "rf-append-spike", ... }` e `hooks/hooks.json` `{ "modules": ["./register.ts"] }`):

```
claude -p --debug --plugin-dir <pasta> --model haiku "Answer only with the exact CANARIO lines ... If none, answer NONE."
```

Para medir a conta de trabalho a partir da pessoal: prefixar `CLAUDE_CONFIG_DIR="<home>/.claude"`
(e o inverso para a pessoal). O debug sai em `<config dir>/debug/*.txt`.

## O que o contrato do engine diz (types de 2.1.292)

- `$.session.append({ message: { type, content }, agentId? })`: anexa de verdade; `type: "user"` vira
  linha `isMeta` que o modelo lê e o usuário não vê como digitada; só blocos de texto nesta versão;
  origem `{ kind: 'plugin', name }`, door `note`. Entra nos requests a partir do próximo topo do loop.
- `session.start` dispara uma vez quando a sessão fica pronta e é aguardado antes do primeiro prompt.
- `/clear`: `session.end` com `reason: 'clear'` e **sem** `session.start` depois.
- Linha da conversa **não** fica no bloco cacheado do system prompt e entra na compactação
  (`session.compact` resume a conversa; a linha anexada pode virar resumo).
- Loads (`--resume`, teleport) **não** são appends: no resume a linha antiga volta do transcript.

## Decidido nesta sessão (pelo usuário)

- Rota de admin descartada: tornar o rainforest mod da organização (managed-settings.json local com
  `extraKnownMarketplaces` directory + `enabledPlugins` + `prependPlugins: ["rainforest-mind@...", "sec-default@builtin"]`,
  clone em `C:\ProgramData`, desinstalar a cópia do GitHub nas duas contas). Funcionaria pela doc, mas troca o
  auto-update do GitHub por `git pull` elevado e põe o guarda também na conta pessoal — "complica demais o que já temos".
  Não reoferecer.
- Console de admin do claude.ai também fora: valeria para a org TOTVS inteira.

## Perguntas que o brainstorm tem de fechar

1. Detecção: como o mod sabe que o compose foi ignorado, para só cair no append quando precisa
   (na pessoal o compose funciona e aproveita o cache)? Candidatos a investigar: presença do
   `cc-plugin-sec-default` entre os plugins carregados, ou um sinal do próprio compose não ter rodado.
2. Resume: a linha anexada já está no transcript — não reanexar em dobro.
3. `/clear`: não há `session.start` depois; as regras precisam voltar por outro gatilho.
4. Compactação: depois de compactar, a linha pode ter virado resumo — reanexar?
5. Custo: ~48 KB fora do cache a cada sessão nova na conta de trabalho; aceitável, ou mandar um recorte?
6. Convivência com o núcleo do hook clássico SessionStart: o núcleo continua, ou sai quando o append entra?

## Achados laterais da sessão de origem (já registrados em outro lugar)

- Ideia `claude-central-despachante` atualizada: agent view (`claude --bg`, `claude agents --json`) resolve
  o "sessão lançada não vira peer"; cada conta tem daemon e roster próprios.
- `cc-plugin-you-should-know` (built-in, radar por `model.fork`) ligado na conta de trabalho para comparar
  com o radar do rainforest antes de pensar em radar próprio.
- `/reload-plugins` acusa `superpowers` habilitado em project settings sem estar instalado — alheio a isto.
