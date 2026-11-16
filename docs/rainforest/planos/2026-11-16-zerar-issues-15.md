# Plano: Rodada 15 — gate de publicação confere gh api, gh release e gh gist (#707)

Design: docs/rainforest/design/2026-11-16-zerar-issues-15.md

## O que não pode quebrar
- Toda forma de `gh issue`/`gh pr` que o gate barra hoje continua barrando: as seções existentes de `bash hooks/testa-gate-publicacao-destino.sh` seguem verdes.
- `gh api` de leitura (`GET`, `graphql` com `query`) e `gh release view` saem 0, mesmo com termo.
- A regex da rede do `gh` perdido não muda (D5).

## Tarefas

### 1. `gh api` de escrita com destino pelo endpoint [tipo: implementar]
atende: D1, D5
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
paralela: nao
busca:
- catalogo | listar --raiz hooks | estendo a função textosDoSegmentoGh de hooks/gate-publicacao-destino.cjs:959 e uso apiEhEscrita de hooks/gate-subagente-sem-gh.cjs:98
desfecho: estender
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de:   if (iApi !== -1 && toks[iApi].toLowerCase() === "api") {
  para:   if (iApi !== -1 && toks[iApi].toLowerCase() === "api-mutante") {
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: testa-gate-publicacao-destino.sh, seção "(#707) gh api, gh release e gh gist", casos "707 api"
prova: `node -e "process.exit(/function textosDoGhApi/.test(require('fs').readFileSync('hooks/gate-publicacao-destino.cjs','utf8'))?0:1)"`
Implementação:
- Função nova `textosDoGhApi(toks, iApi, cmdOriginal, cwd)`: escrita decidida por `apiEhEscrita`; texto = valor de cada campo, arquivo de `-F campo=@arq` e de `--input`, e o comando inteiro só contra a lista de termos; destino pelo endpoint (`repos/<dono>/<repo>`, `:owner`/`{owner}` pelo cwd, `gists` com `public=true`, o resto desconhecido).
- `textosDoSegmentoGh` desvia para ela quando o primeiro posicional depois de `gh` é `api`.
- `ghTextoSegmentos` conta só `issue`/`pr` (D5).
pronto quando: na seção `(#707)` de `bash hooks/testa-gate-publicacao-destino.sh`, os casos `707 api ...` saem 2 com `GH_RESPONSE` público e 0 com privado (`-f`, `--raw-field`, `-F`, `--field`, `-F @arquivo`, `--input`, `:owner/:repo`, `-XPOST`, URL completa); `gists` com `public=true` sai 2; `graphql` com `mutation` sai 2 e com `query` sai 0; GET e `-X GET` saem 0. Placar `0 falha(s)`.

### 2. `gh release create|edit` e `gh gist create` [tipo: implementar]
atende: D2, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 1
paralela: nao
busca:
- catalogo | listar --raiz hooks | estendo a função textosDoSegmentoGh de hooks/gate-publicacao-destino.cjs:959 (tabela VERBOS_GH_TEXTO ao lado)
desfecho: estender
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de:   release: new Set(["create", "edit"]),
  para:   release: new Set([]),
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: testa-gate-publicacao-destino.sh, seção "(#707) gh api, gh release e gh gist", casos "707 release"
prova: `node -e "const s=require('fs').readFileSync('hooks/gate-publicacao-destino.cjs','utf8');process.exit(/release: new Set\(\[\"create\", \"edit\"\]\)/.test(s)&&/gist: new Set\(\[\"create\"\]\)/.test(s)?0:1)"`
Implementação:
- `VERBOS_GH_TEXTO` ganha `release: create, edit` e `gist: create`.
- Tabelas `CURTAS_POR_FAMILIA` e `LONGAS_POR_FAMILIA`: letra fora delas é booleana (`-p`, `-d` do release; `-p`, `-w` do gist).
- Release: `--notes`/`-n` e `--title`/`-t` são texto; `--notes-file`/`-F` é arquivo. Gist: `--desc`/`-d` é texto, posicional é arquivo, `--public`/`-p` torna o destino fixo público; sem a flag, o gist sai 0.
pronto quando: na seção `(#707)`, os casos `707 release ...` saem 2 com público e 0 com privado (`--notes`, `-n`, `--notes-file`, `-F`, `--title`, `-t`, `-p -n`, `-d --notes`, `edit --notes`, `edit -F`, `edit --title`, `-R dono/x`); `gist --public a.md` e `gist -p -d` saem 2 com resposta privada; `gist create a.md` e `-d` sem `--public` saem 0. Placar `0 falha(s)`.

### 3. Arquivo de corpo com BOM e `~` [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 2
paralela: nao
busca:
- catalogo | listar --raiz hooks | estendo a leitura de --body-file de textosDoSegmentoGh em hooks/gate-publicacao-destino.cjs:959 com a função nova lerCorpoDeArquivo de hooks/gate-publicacao-destino.cjs:785
desfecho: estender
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de:   if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return buf.subarray(2).toString("utf16le");
  para:   if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return buf.subarray(2).toString("utf8");
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: testa-gate-publicacao-destino.sh, seção "(#707) gh api, gh release e gh gist", casos "UTF-16LE com BOM"
prova: `node -e "process.exit(/function lerCorpoDeArquivo/.test(require('fs').readFileSync('hooks/gate-publicacao-destino.cjs','utf8'))?0:1)"`
Implementação:
- `lerCorpoDeArquivo(valor, cwd)`: pula stdin e valor da hora, expande `~` pelo `HOME`, normaliza MSYS, resolve contra o cwd e decodifica pelo BOM (`decodificarCorpo`). Usado por `--body-file`, `--notes-file`, `-F @arq`, `--input`, arquivos de gist e pela rede.
pronto quando: na seção `(#707)`, `--body-file` e `--notes-file` em UTF-16LE com BOM e `--body-file ~/x.md` (HOME de areia) com o termo saem 2 no público. Placar `0 falha(s)`.

### 4. Versão 2.16.1 e registro [tipo: docs]
atende: D6, D7, D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: número de versão e texto de registro; não há comportamento a inverter. A coerência se confere pela bateria de versão e pela leitura contra o design.
pronto quando: os manifestos e o selo dizem 2.16.1, `bash scripts/testa-versao.sh` sai com 0 falhas, a linha do `gate-publicacao-destino.cjs` no README cita `gh api`, `gh release` e `gh gist`, e a entrada `## 2.16.1 — 2026-11-16` do CHANGELOG descreve D1 a D4 e o que segue passando (stdin, valor da hora).
