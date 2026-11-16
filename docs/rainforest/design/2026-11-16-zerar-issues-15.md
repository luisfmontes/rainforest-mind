# gate-publicacao confere `gh api`, `gh release` e `gh gist` (#707)

## Objetivo

Desde a #702, o `hooks/gate-publicacao-destino.cjs` confere o texto de `gh issue create|comment|edit|close|reopen` e de `gh pr create|comment|edit|review|merge|close|reopen` que vai para um repositório público. Três escritas de texto livre passam sem conferência: `gh api` com campo ou `--input`, `gh release create|edit` com notas ou título, e `gh gist create --public`. A Issue #707 pede que cada forma saia 2 pelo payload real de PreToolUse com destino público e 0 com destino privado, e que o stdin e o valor resolvido na hora sejam conferidos ou registrados como resíduo aceito.

## Decisões fechadas

Rodada em modo autônomo: cada decisão é a recomendada, e as marcadas *(suposição)* o Luís revisa no PR.

- **D1 — `gh api` de escrita.** Escrita é o que `apiEhEscrita` (exportada por `hooks/gate-subagente-sem-gh.cjs`) já decide: método explícito diferente de `GET`, ou campo/`--input` sem método; `graphql` só com `mutation` (ou query de arquivo). Reuso, não regra nova — porquê: os dois gates têm de concordar sobre o que é escrita.
  - **Texto conferido:** o valor de cada campo (`-f`, `--raw-field`, `-F`, `--field`; o que vem depois do primeiro `=`), o arquivo de `-F chave=@arquivo` e de `--input arquivo` quando legíveis, e o comando inteiro só contra a lista de termos, como na #702.
  - **Destino:** o endpoint, primeiro posicional depois de `api` (aceita `/` inicial e `https://api.github.com/`). `repos/<dono>/<repo>/...` → `<dono>/<repo>`. `{owner}`/`{repo}`/`:owner`/`:repo` → as regras de destino da #702 (cwd, `GH_REPO`, menções). `gists` → D3. Qualquer outro endpoint (`graphql`, `user`, `orgs/...`) ou `--hostname` → destino desconhecido, falha fechada. *(suposição)* O desconhecido só barra quando há achado; e `graphql` de leitura nem chega aqui, porque não é escrita.
- **D2 — `gh release create|edit`.** Texto: `--notes`/`-n`, `--title`/`-t` e o arquivo de `--notes-file`/`-F`. Destino como na #702 (`--repo`/`-R`, `GH_REPO`, cwd). As booleanas da família (`-d`, `-p`, `--draft`, `--prerelease`, `--latest`, `--generate-notes`, `--verify-tag`) não engolem o token seguinte. A tabela de flags curtas passa a ser chaveada por família e verbo, porque `-p`, `-F`, `-f`, `-d` e `-t` mudam de sentido entre `pr`, `release`, `gist` e `api`.
- **D3 — `gh gist create|new`.** Público só com `--public`/`-p`; sem a flag o gist é secreto e o gate o trata como privado. *(suposição: secreto não aparece em lista nem busca.)* Texto: `--desc`/`-d`, cada arquivo posicional legível e o comando inteiro só contra a lista de termos. Pela `api`: `POST gists` com campo `public=true` → público; sem ele → secreto, sai 0; outro método em `gists/<id>` → desconhecido.
- **D4 — Dois resíduos baratos da Issue.** O leitor dos arquivos de corpo detecta BOM (UTF-16LE, UTF-16BE, UTF-8) e decodifica por ele — o `> body.md` do PowerShell 5.1 grava UTF-16LE. E `~`/`~/` no início do caminho expande para o `HOME` do processo. Vale para todo arquivo de corpo deste gate (`--body-file`, `--notes-file`, `-F @arq`, `--input`, arquivos de gist).
- **D5 — A contagem da rede continua só de `issue`/`pr`.** `ghTextoSegmentos` conta só as famílias que a regex da rede conhece; a regex não muda.
- **D6 — Regra de parada da revisão** *(fixada antes do primeiro despacho)*. A base (`55da5f9d`) sai 0 em toda forma de `api`/`release`/`gist`, então "contorno" de família nova não é regressão. Reprova só: (a) célula da matriz do "Pronto quando" que falha; (b) forma de `gh issue`/`gh pr` que a base barra e o HEAD deixa passar; (c) falso positivo de severidade média ou mais (comando comum do dia a dia). O resto é resíduo, registrado aqui, sem commit de conserto — inclusive achado da revisão de segurança automática que der o mesmo resultado na base e no HEAD.
- **D7 — Ordem de cada volta.** Commit e push → baterias longas → triagem do alerta de segurança do commit → `conferir-fluxo.cjs creep` → `exigir revisar` → despacho do revisor. Nenhuma mudança no worktree com revisor em voo.
- **D8 — Versão 2.16.1 (PATCH).** CHANGELOG, as duas `plugin.json` e a linha do gate no README. — porquê: conserto de cobertura de um gate existente, como a D7 da #702.

## Avaliado e descartado

- **Ler stdin ou expandir variável:** o hook não tem o valor; o termo no próprio comando já barra.
- **Alargar a regex da rede do `gh` perdido** (`-R` colado, `.`/`@` no nome da flag): é a peça que já teve retrocesso exponencial e custo quadrático; fica como resíduo.
- **Barrar `gh api graphql` sempre:** consulta de leitura com nome de cliente seria falso positivo diário.

## Varredura

docs/rainforest/varredura/2026-11-16-zerar-issues-15.txt. Só a #707 está aberta no tema. O fluxo que a revelou é o `gate-publicacao-gh` (#702, PR #715). As decisões dele seguem valendo: o comando inteiro conta só contra a lista de termos, o pior destino decide e o marcador `dados-de-exemplo` não isenta. As Issues fechadas do `gate-publicacao-destino` (#419, #494, #410, #409, #322, #237) tratam de falso positivo de detector e de visibilidade, e os detectores não mudam aqui.

## Em aberto

(nenhum)

## Fora de escopo

Resíduos aceitos. A Issue autoriza aceitar o stdin e o valor resolvido na hora. Os demais abaixo são aceitos por mim e vão listados em "Decidido sem você" no PR e no comentário de fechamento.
- **Stdin e valor resolvido na hora:** `--body-file -`, `-F k=@-`, `--input -`, `--notes-file -`, gist `-`, `$f`, `$(...)`, crase.
- **Arquivo escrito pelo próprio comando** por redirecionamento ou `Set-Content` (não existe quando o hook roda).
- **Dado sensível que não é termo e não está em corpo legível** (JID em `printf ... | gh ... -F -`, em `<<<`).
- **`GH_REPO` por `Set-Item`/`New-Item -Path Env:GH_REPO` ou `export "GH_REPO"=`**, e `unset GH_REPO` (falha fechada: o da sessão continua contando).
- **Limites da rede do `gh` perdido:** quebra dentro de `$( )`, contagem em vez de posição, custo quadrático, token não-flag entre família e verbo, `xargs -I{}`, `--body-file` relativo depois de `cd`, `-R` colado e flag com `.`/`@`, e `api`/`release`/`gist` escondidos por aspa ímpar.
- **Here-string do PowerShell com fechamento indentado** e o caso da crase em aspa simples que não discrimina as leituras.
- **Falso positivo de `echo gh issue create --title <termo>`** (falha fechada, só com termo).
- **`gh gist edit` e `gh release upload`.**

## Pronto quando

Payload real de `PreToolUse` na seção `(#707)` de `bash hooks/testa-gate-publicacao-destino.sh`, com o `gh` falso de visibilidade e o termo `termo707` no `HOME` de areia. Cada linha sai **2 com o repositório público e 0 com o privado**:

| Família | Formas |
|---|---|
| `gh api` | `repos/dono/X/issues/3/comments -f body=termo707`; `--raw-field body=termo707`; `-F body=termo707`; `--field body=termo707`; `-F body=@corpo.md`; `--input corpo.json`; `-X PATCH repos/{owner}/{repo}/issues/3 -f body=termo707` (destino pelo cwd) |
| `gh release create` | `--notes termo707`; `-n termo707`; `--notes-file notas.md`; `-F notas.md`; `--title termo707`; `-t termo707`; `-p -n termo707` (booleana não engole) |
| `gh release edit` | `--notes termo707`; `-F notas.md`; `--title termo707` |

E também:
- `gh gist create --public a.md` e `gh gist create -p -d termo707 b.md` saem 2; `gh gist create a.md` sai 0.
- `gh api graphql -f query='mutation { ... termo707 ... }'` sai 2; `gh api graphql -f query='query { search(query:"termo707") }'` sai 0.
- `gh api gists -f public=true -f 'files[a.md][content]=termo707'` sai 2; sem `public=true`, 0.
- `--body-file` em UTF-16LE com BOM e `--body-file ~/x.md` (HOME de areia) com o termo saem 2 no público.
- Saem 0: `gh api repos/dono/publico/issues` (GET), `gh api -X GET search/issues -f q=termo707`, `gh release view v1`.
- As seções existentes da bateria seguem com 0 falhas.
