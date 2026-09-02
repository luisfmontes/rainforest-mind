# Handover — a frente dos vigias: um morto, um que nunca funcionou, um que suja o repo

**Data:** 2026-09-02
**Para:** a sessão paralela que vai atacar os vigias
**Estado do repo:** `main` em `57485b0`, versão 0.80.0, PRs #141 (portaria) e #139
(gate de worktree) mergeadas. Comece de `origin/main` limpo.

> Se você só for ler um parágrafo: dos cinco vigias agendados, **dois estão mortos
> desde 12/08** (gatilho com `EndBoundary` vencido — a tarefa fica `Ready` e
> `NextRunTime` vazio, que é o modo de falha silencioso do agendador), o **backup
> do FOCO.md nunca rodou com sucesso em nenhum vigia** (a raiz passada é a do
> plugin, e o FOCO.md mora na raiz de dados), e **cada erro registrado suja o
> repositório** porque o log é gravado em CRLF e reprova a catraca de encoding
> da própria casa. Os três estão reproduzidos abaixo com comando e saída.

## V1 — `vigia-tickets` está morto há 20 dias, e parece saudável

`Get-ScheduledTask` para as cinco tarefas:

```
Nome                Estado UltimaExec          Resultado Proxima
----                ------ ----------          --------- -------
batedor-repos        Ready 28/08/2026 09:00:00         0 04/09/2026 09:00:00
jardineiro-ideias    Ready 28/08/2026 15:52:00         0 04/09/2026 15:52:00
sentinela-foco       Ready 01/09/2026 08:23:11         0 02/09/2026 07:52:00
vigia-tickets-manha  Ready 11/08/2026 08:52:01         0
vigia-tickets-tarde  Ready 11/08/2026 14:52:00         0
```

`Proxima` **em branco** nas duas últimas. O gatilho:

```
Enabled       : True
EndBoundary   : 2026-08-12T00:00:00
StartBoundary : 2026-08-06T08:52:00
DaysOfWeek    : 62      (seg-sex)
```

`EndBoundary` de 12/08 — a janela do gatilho fechou. O agendador não desabilita
a tarefa nem marca erro: `Enabled: True`, `State: Ready`, `LastTaskResult: 0`.
Os três sinais que uma pessoa checa dizem "saudável", e a tarefa não roda desde
11/08. O único campo que denuncia é o `NextRunTime` vazio.

**Isso é o mesmo padrão do Issue #142** (o guarda que respondia "sujo" para tudo):
o instrumento responde, a resposta é plausível, e mede outra coisa. Vale enxertar
no acervo da regra 12 como segunda ocorrência — a heurística lá é "medição
uniforme demais é suspeita"; esta é a irmã dela, **"campo vazio não é campo ok"**.

De carona, na ação das duas tarefas: `-Vigia  vigia-tickets` com **espaço duplo**.
Não confirmei se o PowerShell engole; confira antes de reagendar.

## V2 — o backup do FOCO.md nunca funcionou, em vigia nenhum

Toda ronda de todo vigia termina com a mesma linha no `ERROS.md`:

```
- 2026-08-28 09:01 [batedor-repos]: backup do FOCO.md falhou (exit 1): erro: nao achei o FOCO.md em ...\rainforest-mind
- 2026-08-28 15:52 [jardineiro-ideias]: backup do FOCO.md falhou (exit 1): ...
- 2026-08-31 09:32 [sentinela-foco]: backup do FOCO.md falhou (exit 1): ...
- 2026-09-01 08:25 [sentinela-foco]: backup do FOCO.md falhou (exit 1): ...
```

A cadeia, reproduzida:

- `vigias/run-vigia.ps1:5` — `$root = if ($env:RFM_ROOT) { $env:RFM_ROOT } else { Split-Path -Parent $PSScriptRoot }`
  → sem `RFM_ROOT` no ambiente da tarefa agendada, isso é a **raiz do repositório do plugin**.
- `vigias/run-vigia.ps1:206` — passa esse `$root` como `-Root` para o `backup-estado.ps1`.
- `vigias/backup-estado.ps1:72` — `node $foco backup --raiz $Root`.

E o `foco.cjs` resolve raiz de **dados**, não de repositório:

```
$ node scripts/foco.cjs caminho --raiz "<raiz do repo do plugin>"
<raiz do repo do plugin>\FOCO.md   (NÃO EXISTE — foco ainda não declarado nesta raiz)

$ node scripts/foco.cjs caminho
~/.rainforest/FOCO.md
```

O default está certo; quem passa `--raiz` errado é o vigia. **O backup que existe
para proteger o FOCO.md nunca protegeu nada** — e o comentário em
`backup-estado.ps1:57-59` conta que ele nasceu justamente de um incidente em que
o FOCO.md do usuário foi para a main sem estar commitado. A defesa foi escrita e
nunca chegou a rodar.

Suspeita a confirmar, não confirmada por mim: `RFM_ROOT` pode estar definido na
sessão interativa e ausente na tarefa agendada, o que faria isso passar em teste
manual e falhar em produção. Mede com `printenv RFM_ROOT` e comparando com o que
a tarefa agendada enxerga.

## V3 — o vigia grava o log de erro em CRLF, e reprova a catraca da própria casa

```
$ node scripts/conferir-encoding.cjs
RECUSADO — problema(s) de encoding encontrado(s).
  eol=lf 	vigias/ERROS.md  [crlf]  fim de linha mixed na arvore de trabalho (esperado LF)
EXIT=2

$ git show HEAD:vigias/ERROS.md | file -
/dev/stdin: Unicode text, UTF-8 text
$ file vigias/ERROS.md
vigias/ERROS.md: Unicode text, UTF-8 text, with CRLF, LF line terminators
```

Causa: `backup-estado.ps1:53` — `$linha | Out-File -Append -Encoding utf8 $destino`.
`Out-File` no PowerShell 5.1 termina linha com CRLF. O arquivo commitado é LF, o
append é CRLF, o resultado é **mixed**, e a catraca de encoding do repositório
recusa. Efeito prático: **cada erro que um vigia registra acende uma bateria
vermelha no repositório inteiro** — e como V2 garante um erro por ronda, isso é
permanente.

Os três se compõem: V2 produz um erro por ronda, V3 grava esse erro no formato
que quebra o repo, e V1 esconde que dois vigias nem chegam a produzir erro
porque não rodam.

**Deixei o `vigias/ERROS.md` modificado e não commitado de propósito** — é a
evidência viva do V3. Se você preferir a árvore limpa antes de começar, regrave
em LF e commite; só não perca o registro de que ele chegou assim.

## O que deu certo

- **O `ERROS.md` cumpriu o papel dele.** Os quatro vigias registraram a falha do
  backup a cada ronda, com data e nome. O defeito estava anotado em texto plano
  desde 28/08 — o que faltou não foi instrumentação, foi alguém ler o arquivo.
  É argumento a favor de o `conferir-saude` (ou o próprio sentinela) olhar o
  `ERROS.md` e subir contagem de erro recente para a sessão.
- **A catraca de encoding pegou o V3 sem ninguém procurar por ele.** Apareceu na
  bateria do repositório, não numa auditoria. Gate genérico achando defeito que
  ninguém suspeitava é o argumento inteiro para gates genéricos.

## Propostas

**P1 — Reagendar `vigia-tickets` sem `EndBoundary`, e conferir o espaço duplo.**
O gatilho precisa nascer sem janela de término, ou com uma folga que ninguém
alcance. Reagendar é alterar ambiente do usuário (regra 15): **pergunte antes**,
não execute direto.
*Destino:* o script de instalação dos vigias + confirmação humana.

**P2 — Uma bateria que reprova quando um vigia agendado tem `NextRunTime` vazio.**
É a trava mecânica que faltou: sem ela, P1 conserta hoje e o próximo
`EndBoundary` vencido passa igual daqui a seis meses. A checagem é uma linha de
`Get-ScheduledTaskInfo` e vale para os cinco.
*Destino:* `scripts/testa-vigias-agendados.sh` (novo) + `conferir-saude`.

**P3 — Consertar a raiz do backup, e cobrir com mutação.** `run-vigia.ps1` deve
passar a raiz de **dados**, não a do plugin — ou `backup-estado.ps1` deve deixar
o `foco.cjs` resolver sozinho (não passar `--raiz`). Conserto de uma linha; o
que importa é a catraca: a mutação tem de matar, senão o teste não mede.
*Destino:* `vigias/run-vigia.ps1` + `scripts/testa-backup-estado.sh`.

**P4 — `Registrar-Erro` grava em LF.** Trocar `Out-File -Append` por escrita
explícita sem CRLF (`[IO.File]::AppendAllText` com terminador `\n`), e uma
bateria que grava uma linha pelo caminho real e roda o `conferir-encoding` em
cima.
*Destino:* `vigias/backup-estado.ps1` + bateria nova.

**P5 — "Campo vazio não é campo ok" entra no acervo.** Irmã da heurística que o
Issue #142 plantou. O agendador respondeu `Ready` / `Enabled: True` /
`LastTaskResult: 0` para uma tarefa morta; o único sinal verdadeiro estava num
campo em branco, e branco lê-se como "nada de errado".
*Destino:* `skills/rainforest-mind/references/regra-12.md`.

**P6 — O `ERROS.md` sobe para a sessão.** Erro registrado que ninguém lê é igual a
erro não registrado; este ficou cinco dias. Uma linha na abertura quando houver
erro de vigia nas últimas N rondas.
*Destino:* hook de SessionStart / `conferir-saude`. **Pendente** — decidir se é
a abertura (que já está no teto de bytes) ou a saúde.
