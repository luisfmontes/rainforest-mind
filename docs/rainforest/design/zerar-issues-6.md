# Zerar as Issues abertas, rodada 6 — regra 6 e as 3 da rodada 5

## Objetivo

Fechar as 4 Issues abertas em 2026-09-17 (#291–#294): dar à regra 6 a fronteira
de repo que faltava e consertar os três restos medidos da rodada 5.

## O que foi medido, e em quê

Base: `origin/main` @ `7e8dd298`, nesta máquina, 2026-09-17. Dois agentes de
medição em worktree isolado, sem editar arquivo versionado; os pontos que
sustentam decisão foram re-conferidos pela janela principal.

| # | Reproduz? | Causa em arquivo:linha | Arquivos do conserto |
|---|---|---|---|
| 291 | sim — o núcleo diz "atrapalha … conserta na hora" sem fronteira de repo; a elaboração diz "bloqueia" e "não sobe como Issue" | `skills/rainforest-mind/SKILL.md:90-92`, `references/regra-06.md:11,51` | os dois + `hooks/testa-contexto-sessao.sh` (catraca `NUCLEO_ESPERADO`, folga 103 B) |
| 292 | sim — com `para:` no-op, itens 9 e 13 dão `ok` e o stderr traz `MODULE_NOT_FOUND`; **item 15 (`:613`) idem**, não citado na Issue | `scripts/testa-foco.sh:219,246,613` gravam o mutante em `$SBP`, e `foco.cjs` faz `require('./lib/...')`; stderr em `/dev/null` | `scripts/testa-foco.sh` |
| 293 | sim, os dois | marcador: `gate-verificador-staged.cjs` tem 0 ocorrências; `temMarcadorDados` é privada em `gate-publicacao-destino.cjs:309-317` e testa o **arquivo inteiro**. Toggle: chave ausente de `CHAVES`, `ligado()` devolve `true` para desconhecida (`hooks/lib/config.cjs:324`) | `hooks/lib/` (nova), os dois gates, `hooks/lib/config.cjs`, baterias |
| 294.1 | sim — sem `PYTHONDONTWRITEBYTECODE`, a seção 20 continua `ok` | asserção olha `$CAIXA/__pycache__` (`testa-conferir-mutacao.sh:856`), a bateria roda em `raizExecucao` (`conferir-mutacao.cjs:513`) | `scripts/testa-conferir-mutacao.sh` |
| 294.2 | não hoje — 0 diretórios `conferir-mutacao-*` no `$TEMP` | sem varredura; `process.on('exit')` não cobre morte externa | `scripts/conferir-mutacao.cjs`, bateria |
| 294.3 | sim — "nunca numa cópia" em 10 arquivos | fonte `referencias/perfil-de-trabalho.md`, replicada por `scripts/perfil.cjs --aplicar` nos 9 `agents/*.md` | fonte + 9 agentes via `--aplicar` |
| 294.4 | sim — sem guarda de plataforma | `hooks/lib/cwd-efetivo.cjs:266-270`; CI só `windows-latest`; com guarda, `testa-cwd-efetivo.sh` 47/0 e `testa-gate-worktree.sh` 204/0 | `hooks/lib/cwd-efetivo.cjs` |
| 294.5 | sim — espelho sem o "só corta se resolver" | `testa-contexto-sessao.sh:2802-2811` vs `contexto-sessao.cjs:1166-1188` | `hooks/testa-contexto-sessao.sh` |

Descartado na medição: `testa-medir-injecao.sh`, `testa-estado.sh` e
`testa-conferir-publicacao.sh` também gravam mutante em `$SBP`, mas os alvos
não fazem import relativo (`medir-injecao.py` só usa stdlib) — não têm o defeito
da #292.

## Decisões fechadas

- **D1 — Regra 6: conserto na hora vale só no repo da sessão; defeito em repo alheio vira Issue no repo dono + `Q` com recomendação, sem worktree, commit ou PR; o peso do defeito não move a fronteira** — porquê: #291 — a regra dizia o quê e quando, não onde, e a leitura literal autorizou commit no repo do vizinho com outra sessão ativa nele. A recomendação da `Q` pode ser "consertar agora" (caso da statusline, 2026-08-18): a fronteira é de autorização, não de mérito.
- **D2 — O limiar é "atrapalha", não "bloqueia", e núcleo e elaboração passam a dizer o mesmo; no repo da sessão o commit é o registro, e só vira Issue o que não for consertado** — porquê: o usuário escolheu "atrapalha" (ferramenta ruidosa se conserta, memória de 2026-08-18); a divergência entre os dois textos foi o que deixou a leitura mais permissiva vencer.
- **D3 — #291 só muda texto; sem hook que avise commit em repo diferente do da sessão** — porquê: a portaria registra e não barra (regra 10); trava nova pede design próprio.
- **D4 — Registrar o incidente da #291 em `regra-06.md`, com linha `re-verificar:`** — porquê: é o formato das elaborações; sem o incidente, a próxima leitura literal refaz o erro.
- **D5 — #292: os itens 9, 13 e 15 gravam o mutante dentro de `scripts/` (padrão do item 17, removido ao fim), capturam o stderr e assertam ausência de `MODULE_NOT_FOUND` antes de aceitar a detecção** — porquê: sem a asserção de stderr, qualquer outro crash volta a fingir detecção; o item 15 tem o mesmo defeito no mesmo arquivo.
- **D6 — #293: `temMarcadorDados` vai para `hooks/lib/` e passa a olhar só as primeiras 5 linhas, nos dois gates; `gate-verificador-staged` pula o arquivo marcado** — porquê: escolha do usuário. "Qualquer linha" isenta todo arquivo que só **cita** o marcador (comentário, doc, a própria lib) da varredura de credencial.
- **D7 — #293: `gate-verificador-staged` entra em `CHAVES` como `boolean`, padrão `true`** — porquê: é o que o cabeçalho do hook já anuncia (`gate-verificador-staged.cjs:30`).
- **D8 — #294.1: a checagem de `__pycache__` vai para dentro da bateria de fixture, que roda na cópia; a asserção sobre `$CAIXA` sai** — porquê: é o único lugar em que o bytecode existiria; expor `raizExecucao` ou `--manter-copia` só para teste acrescentaria superfície de produção.
- **D9 — #294.2: na abertura, `conferir-mutacao.cjs` apaga diretórios `conferir-mutacao-*` (inclusive `-git-*`) do `os.tmpdir()` com mtime acima de 24 h** — porquê: escolha do usuário; timeout externo é comum aqui (Bash tool corta em 10 min, mutação vai até 1 h) e o nome não tem PID, então idade é o único critério seguro.
- **D10 — #294.3: a frase passa a distinguir clone fiel via catraca (`conferir-mutacao.cjs`, aceito) de fixture isolada ou cópia à mão (proibida); edita-se a fonte e o `perfil.cjs --aplicar` replica** — porquê: o checador garante identidade entre as cópias; editar os agentes à mão quebra o `--conferir`.
- **D11 — #294.4: `normalizarMsys` devolve o caminho intacto fora de `win32`** — porquê: fora do Windows `/c/x` é caminho POSIX legítimo; medido sem regressão nas duas baterias.
- **D12 — #294.5: as asserções `SOBRA_22_*` passam a medir a saída real de `montarContexto` com o fixture `FOCO_MUITOS`; `medir_sobra` sai** — porquê: espelho de código nasce desatualizado, e este já nasceu.

## Avaliado e descartado

- **Hook que avisa commit em repo diferente do da sessão (#291)** — descartado por D3.
- **Manter "qualquer linha" no marcador (#293)** — isenta arquivo que só cita o marcador; descartado por D6.
- **`--manter-copia` ou log de `raizExecucao` para o teste do `.pyc`** — superfície de produção para servir teste; descartado por D8.
- **Fechar #294.2 como não reproduzido** — o gatilho (morte externa) é rotina neste ambiente; descartado por D9.

## Fora de escopo

- O conserto dos dois defeitos que originaram a #291: moram no repo alheio e já estão em PR lá.

## Em aberto

- (nada)
