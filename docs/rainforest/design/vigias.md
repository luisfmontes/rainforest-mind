# Design — os vigias parados: dois mortos, um backup que nunca rodou, um log que suja o repo

**Slug:** `vigias` · **Data:** 2026-09-01 · **Branch:** `fluxo/vigias` · **Base:** `origin/main` @ `760bccc`

Entrada: o handover `relatorios/2026-09-02-handover-vigias-parados.md`, escrito por
outra sessão. Tudo abaixo foi **reconfirmado por execução nesta janela** — o handover
é a pista, não a evidência. Uma coisa mudou na reconfirmação, e está marcada.

## Os defeitos

### V1 — `vigia-tickets` está morto desde 11/08 e os três sinais dizem "saudável"

```
Nome                Estado Ultima              Res Proxima
batedor-repos        Ready 28/08/2026 09:00:00   0 04/09/2026 09:00:00
jardineiro-ideias    Ready 28/08/2026 15:52:00   0 04/09/2026 15:52:00
sentinela-foco       Ready 01/09/2026 08:23:11   0 02/09/2026 07:52:00
vigia-tickets-manha  Ready 11/08/2026 08:52:01   0
vigia-tickets-tarde  Ready 11/08/2026 14:52:00   0
```

```
=== vigia-tickets-manha ===
Enabled       : True
StartBoundary : 2026-08-06T08:52:00
EndBoundary   : 2026-08-12T00:00:00
DaysOfWeek    : 62
ACAO: [powershell.exe] ARGS: [... -File ...\run-vigia.ps1 -Vigia  vigia-tickets -Cwd "C:\Projetos\comms-vigia"]
```

`EndBoundary` de 12/08 fechou a janela do gatilho. O agendador **não** desabilita a
tarefa nem marca erro: `State: Ready`, `Enabled: True`, `LastTaskResult: 0`. Os três
campos que uma pessoa checa mentem em coro. O único que denuncia é o `NextRunTime`
**vazio** — e branco lê-se como "nada de errado".

Confirmado também o espaço duplo em `-Vigia  vigia-tickets`.

### V2 — o backup do FOCO.md nunca rodou, em vigia nenhum

- `vigias/run-vigia.ps1:5` — `$root` cai em `Split-Path -Parent $PSScriptRoot` quando não há `RFM_ROOT`
- `vigias/run-vigia.ps1:206` — passa esse `$root` como `-Root`
- `vigias/backup-estado.ps1:72` — `node $foco backup --raiz $Root`
- `scripts/foco.cjs` resolve raiz de **dados**, não de repositório

**Divergência do handover.** Ele suspeitava que `RFM_ROOT` existisse na sessão
interativa e faltasse na tarefa agendada — o que faria o defeito passar em teste
manual. Medido: `printenv RFM_ROOT` → **exit 1**. A variável não está definida em
lugar nenhum. Falha nas duas pontas, e é mais simples do que se pensava.

### V3 — `Registrar-Erro` grava CRLF e reprova a catraca da própria casa

`vigias/backup-estado.ps1:53` usa `Out-File -Append -Encoding utf8`, que no
PowerShell 5.1 termina linha em CRLF. Reproduzido byte a byte: um arquivo gravado em
LF puro, seguido de um `Out-File -Append -Encoding utf8`, termina em `0d 0a` — CRLF.

Commitado em LF, append em CRLF, resultado **mixed**, `conferir-encoding.cjs` recusa
com exit 2. Como o V2 garante um erro por ronda, a bateria vermelha é permanente.

### V4 — NOVO: o `ERROS.md` está com mojibake e a catraca é cega para ele

Não está no handover. No `vigias/ERROS.md` **commitado**, onde deveria estar a palavra
"não", os bytes são:

| byte(s) | caractere |
|---|---|
| `6e` | `n` |
| `e2 94 9c` | U+251C, box drawing |
| `c3 ba` | U+00FA |
| `6f` | `o` |

A palavra saiu do node como UTF-8 (`6e` + `c3 a3` + `6f`), o PowerShell decodificou
`c3 a3` no codepage **OEM** do console (CP850) e regravou em UTF-8. Round-trip de
mojibake, gravado e commitado.

E `node scripts/conferir-encoding.cjs` sai **exit 0**. Motivo, em
`scripts/conferir-encoding.cjs:134`: a detecção só casa a assinatura **CP1252**
(`Ã`/`Â`/`â€` seguido de membro de `CP1252_ESPECIAIS`). A assinatura OEM não está na
rede.

É a mesma espécie de peixe que o gate existe para pegar, por um buraco que ninguém
tinha medido. Vale mais que os outros três: ele diz que o gate **prova menos do que
promete**, e todo verde dele até hoje vale um pouco menos.

## Como os quatro se compõem

V2 produz um erro por ronda → V3 grava esse erro em CRLF e quebra o repo → V4 grava
o mesmo erro corrompido e o gate não vê → V1 esconde que dois vigias nem chegam a
produzir erro, porque não rodam.

## O que as Issues já diziam

- **#118 (FECHADA em 26/08)** — "O backup diario do sentinela nunca fez backup".
  Fechada, e **o defeito do título continua vivo**. O conserto tirou o `git push`
  perigoso e criou o `backup-estado.ps1`; o backup nunca passou a funcionar. O
  `ERROS.md` registra a falha desde **27/08 — o dia seguinte ao fechamento**.
  Não é reincidência: é uma issue fechada sem o critério de pronto dela ser rodado.
- **#112 (FECHADA)** — decidiu que a raiz do `ERROS.md` é o PLUGIN. Continua valendo;
  o V2 não a contradiz (o `ERROS.md` fica no plugin, o FOCO.md vem dos dados).
- **#124 (ABERTA)** — o `ERROS.md` é rastreado em repo público e recebe caminho de
  máquina interpolado. **Cai na mesma função `Registrar-Erro` que o V3 obriga a
  reescrever.** Entra no escopo: reescrever a função duas vezes é a dívida que o
  fluxo 9 já pagou uma vez.

## Decisões

**D1 — a raiz do backup.** `run-vigia.ps1` para de passar raiz de plugin. Entre passar
a raiz de dados e deixar o `foco.cjs` resolver sozinho, decide-se na implementação,
com o motivo escrito no código. *Porque* o default do `foco.cjs` está certo e quem
erra é o chamador.

**D2 — `Registrar-Erro` reescrita uma vez só, cobrindo V3 + V4 + #124.** LF explícito
(`AppendAllText` com terminador de linha único), UTF-8 sem BOM, saneamento de caminho
de máquina antes de gravar, e o texto chegando sem passar pelo codepage OEM. *Porque*
são três defeitos na mesma função e três passadas nela custam três revisões.

**D3 — o gate de encoding aprende a assinatura OEM, e o passado é backfill.** A tabela
sai da faixa `0x80`–`0xBF` do CP850, derivada como a `CP1252_ESPECIAIS` foi. As linhas
corrompidas do `ERROS.md` são reescritas, **nenhuma apagada**. *Porque* o registro
histórico é a evidência de que o backup falha desde 28/08, e vale mais que a limpeza.

**D4 — bateria que reprova `NextRunTime` vazio.** `scripts/testa-vigias-agendados.sh`.
Ela nasce **vermelha** de propósito, e fica verde quando o D6 rodar. Pula limpo onde
não há PowerShell, não há tarefa do plugin, ou o toggle `vigias` está desligado.
*Porque* sem ela o D6 conserta hoje e o próximo `EndBoundary` vencido passa igual
daqui a seis meses.

**D5 — "campo vazio não é campo ok" entra no acervo da regra 12.** Irmã da heurística
que a Issue #142 plantou ("medição uniforme demais é suspeita"). O arquivo
`references/regra-12.md` está em 9.277 B contra teto de 10.500 B — cabe, e o handover
reservou esse arquivo para esta janela. *Porque* o padrão já apareceu duas vezes em
duas semanas, em instrumentos diferentes.

**D6 — reagendar as duas tarefas mortas.** Gatilho sem `EndBoundary`, espaço duplo
corrigido. Altera ambiente do usuário (regra 15) — **autorizado por ele em
2026-09-01**. *Porque* é o único item que faz os vigias voltarem a rodar.

**D7 — o `ERROS.md` sobe pelo `conferir-saude`, não pela abertura.** *Porque* o payload
do SessionStart já bate no teto de bytes — foi por isso que as regras 4–17 nunca
chegaram a sessão nenhuma — e mais uma linha lá empurra outra coisa para fora.

## Fora de escopo, e por quê

- **`escreve: true` na portaria.** Admitir agente que edita não é diff de manifesto:
  a portaria nega em runtime (`hooks/portaria.cjs:421`) e no lint com a mesma razão
  — "depende do isolamento por worktree, fora de escopo no fluxo 9". Implementá-lo
  aqui colidiria de frente com `fluxo/portoes`, a sessão paralela ativa. O código
  desta entrega é escrito na janela principal; `planejador` e `revisor`, que estão
  admitidos, são despachados nos estágios deles.
- **Tirar o `ERROS.md` do versionamento** (a segunda família da #124). Decisão maior
  que esta entrega, e o D2 fecha o modo de falha imediato.

## Cerca com `fluxo/portoes`

Não nos tocamos em `vigias/`, `scripts/conferir-encoding.cjs` nem `scripts/saude.cjs`.
Encostos: `README.md` (hunks distintos) e
`skills/rainforest-mind/references/regra-12.md`, **reservado a esta janela** pelo
handover. Quem mergear primeiro avisa; o outro rebasa antes do `revisar`.

## Achado de carona: o gate de publicação lê dump hexadecimal como telefone

A primeira versão deste arquivo trazia a saída crua de `xxd` para provar o V4, e o
`gate-publicacao-destino.cjs` **bloqueou a gravação** apontando duas linhas como
`[telefone]`. É falso positivo: são colunas de offset e bytes. O dump virou tabela
aqui, sem desligar o gate — mas o caso vale registro, porque provar defeito de
encoding *exige* colar bytes, e hoje isso esbarra na trava. Vira Issue no `fechar`.
