# Regra 10 — runtime do agente (Claude ou Codex)

Emenda de 2026-09-08, separada de `regra-10-portaria.md` pelo mesmo motivo que
aquele arquivo nasceu: a catraca de bytes de um `reference` (D9, Issue #73)
estourou, e consultar uma regra tem de continuar custando menos de 3k tokens.
Design em `docs/rainforest/design/2026-09-08-agentes-em-codex.md`.

## O campo `runtime` no manifesto

`.rainforest/agentes.json` aceita, por agente, `runtime: "claude" | "codex"`.
Ausente significa `claude`; qualquer outro valor **nega** com motivo instrutivo,
no mesmo espírito da checagem de forma de `escreve`.

```json
{
  "versao": 1,
  "agentes": {
    "revisor":  { "estagios": ["revisar"],  "escreve": false, "runtime": "claude" },
    "executor": { "estagios": ["executar"], "escreve": true,  "runtime": "codex" }
  }
}
```

## Override por briefing

Uma linha isolada `Runtime: codex` (ou `Runtime: claude`) no bloco 1 do briefing
vence o manifesto. A portaria reconhece a linha com a regex
`/^\s*runtime:\s*codex\s*$/im` (`hooks/portaria.cjs`, função `runtimeEfetivo`):
case-insensitive, linha inteira. Precedência: linha no briefing > manifesto >
`claude`. Quando o usuário diz "faz no codex", "roda no codex" ou equivalente,
quem despacha põe essa linha como **primeira** do briefing.

Linha opcional `Despacho: <caminho>` no mesmo bloco diz ao agente onde está
`scripts/despachar-codex.cjs`. Sem ela, o agente tenta `$CLAUDE_PLUGIN_ROOT` e
depois a raiz do repositório atual. Ela existe porque o worktree de um
subagente nasce da `origin/main`: numa branch que ainda não foi integrada, o
script não está lá, e o plugin instalado pode ser versão anterior.

## O que a portaria faz, e o que não faz

Toda linha `allow` de `.rainforest/portaria/despachos.jsonl` traz `"runtime"`,
inclusive no default (`"runtime":"claude"`, caso 21 de
`hooks/testa-portaria-nucleo.cjs`). Linha `deny` ainda **não** traz o campo:
folga conhecida desde 2026-09-08, não decisão.

A portaria só **registra** o runtime; ela não despacha nada. Quem age é o
próprio agente: o bloco `<!-- ponte-codex -->` no topo de cada `agents/*.md`
manda, diante da linha `Runtime: codex`, gravar o briefing num arquivo e fazer
uma única chamada a `scripts/despachar-codex.cjs`, que roda `codex exec` com
sandbox `read-only` ou `workspace-write` conforme `--escreve`, e devolver a
saída literal. Sem a linha, o bloco é ignorado e o agente segue o método dele.

## O commit é da ponte, não do Codex

O sandbox `workspace-write` do Codex nega escrita em `.git`, e `--add-dir` não
reabre (medido em 2026-09-08 com o gitdir exato do worktree: `index.lock:
Permission denied`). O Codex edita; o agente Claude, de volta ao worktree,
faz `git add -A && git commit` se `git status --short` não estiver vazio. No
Windows o Codex roda comandos em PowerShell 5.1: briefing para ele não usa `&&`.
