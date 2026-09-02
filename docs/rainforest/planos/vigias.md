# Plano — vigias parados

**Slug:** `vigias` · **Design:** `docs/rainforest/design/vigias.md`
**Base:** `origin/main` @ `760bccc` · **Branch:** `fluxo/vigias`

Sete tarefas. **Nenhum fan-out**: a portaria nega `escreve: true` por desenho, e nesta
sessão ela resolve o estágio ativo pelo `cwd` da janela (a do `fluxo/portoes`), então
nem os agentes read-only são despacháveis. Tudo é escrito na janela principal.

## Levantamentos que mudaram o plano

Dois fatos medidos depois do design, e os dois alargam T2:

1. **O CRLF não está só no `backup-estado.ps1`.** `run-vigia.ps1` grava no `ERROS.md`
   em **quatro** sítios (linhas 31, 46, 74 via `Stop-ComErro`, e 140), todos com
   `Out-File -Append -Encoding utf8`. Consertar só o `backup-estado.ps1` deixa
   três quartos do defeito em pé.
2. **`conferir-publicacao.cjs` NÃO sabe sanear caminho de máquina.** A única regra
   parecida nele é sobre JID de WhatsApp (`scripts/conferir-publicacao.cjs:50`,
   marcador `<jid-do-contato>`). Então a #124 exige saneamento novo — não é "só
   chamar o que já existe". Os três sítios que interpolam caminho de usuário são
   `run-vigia.ps1:80` (`$configPath`), `:131` (`$bridgeLauncher` + `$configPath`) e
   `:150` (`$configPath`).

**Restrição de arquivo, herdada e não negociável:** `vigias/backup-estado.ps1` é
**ASCII puro de propósito** (cabeçalho do próprio arquivo: o PowerShell 5.1 lê `.ps1`
sem BOM como CP-1252, e um travessao em UTF-8 abre string e quebra o parser 60 linhas
adiante). Vale para `run-vigia.ps1` também. **Hífen, nunca travessão.**

---

## T1 — a raiz do backup do FOCO.md (D1)

**Toca:** `vigias/run-vigia.ps1`, `scripts/testa-backup-estado.sh`
**Depende de:** nenhuma · **Paralelizável:** sim

`run-vigia.ps1:206` para de passar raiz de plugin como `-Root`. O `foco.cjs` já
resolve a raiz de dados corretamente sozinho; o chamador é quem erra. Escolha a
implementar com o motivo escrito no código: deixar o `foco.cjs` resolver (e então
`-Root` de `backup-estado.ps1` fica órfão e precisa ser resolvido explicitamente —
removido ou documentado), ou passar a raiz de dados resolvida pela via canônica do
plugin (`hooks/lib/raiz.cjs`). **Nenhum caminho desta máquina no código** — o repo é
público.

**Critério de pronto:**
- `bash scripts/testa-backup-estado.sh` → exit 0, com **mais casos** que na base
  (a base tem N; cole N e o novo número).
- Caso novo, nomeado na saída: sem `RFM_ROOT` no ambiente, o backup **acha o FOCO.md
  e cria a cópia**. A saída tem de nomear o arquivo de cópia criado.
- **Mutação:** volte `-Root $root` (raiz de plugin) em `run-vigia.ps1` → a bateria
  fica **vermelha** na asserção do caso novo. Cole a linha `FALHA ...`. Verde na
  mutação = a bateria não mede.

---

## T2 — uma função de escrita só, cobrindo CRLF + OEM + caminho de máquina (D2, #124)

**Toca:** `vigias/run-vigia.ps1` (4 sítios), `vigias/backup-estado.ps1` (2 sítios),
`scripts/testa-registrar-erro.sh` (novo), `vigias/erros.ps1` (novo — a porta única),
`scripts/testa-backup-estado.sh` e `scripts/testa-erros-md-raiz.sh`

> **Emenda de 2026-09-02, feita depois da revisão.** Os três últimos não estavam
> nesta lista quando o plano foi escrito. `vigias/erros.ps1` nasceu porque seis
> cópias da mesma escrita não se consertam em seis lugares; as duas baterias
> tiveram de ser tocadas porque o dot-source virou dependência de execução das
> caixas de areia delas, e porque a trava da #112 filtrava só comentário de
> linha e passou a acusar o bloco `<# #>` que explica a própria regra. É
> consequência direta da T2, não escopo novo — mas o plano tem de dizer, senão o
> rastro de "que arquivo esta tarefa podia tocar" fica furado.
**Depende de:** nenhuma · **Paralelizável:** com T1 não (mesmo arquivo) — **serial após T1**

Uma única função de escrita no `ERROS.md`, usada pelos seis sítios, com três
propriedades. Cada uma tem critério próprio; um "a função foi reescrita" não fecha
nenhuma delas.

**T2a — LF.** `[IO.File]::AppendAllText` com terminador de linha único e UTF-8 **sem
BOM**. Cuidado: `Out-File -Encoding utf8` no 5.1 escreve BOM ao criar arquivo novo.

**T2b — sem mojibake OEM.** O texto que vem do `node` (stderr/stdout) não pode
atravessar o codepage OEM do console antes de ser gravado. Decida onde interceptar
(`[Console]::OutputEncoding`, ou ler a saída como bytes) e escreva o motivo no código.

**T2c — saneamento de caminho de máquina (#124).** Antes de gravar, caminho de
usuário vira marcador. Fica na função por onde todos passam, não na disciplina de
quem escreve a mensagem.

**Critério de pronto — um por propriedade:**
- **T2a:** `bash scripts/testa-registrar-erro.sh` executa o artefato **real**
  (`backup-estado.ps1`, não uma cópia do bloco), grava uma linha, e
  `node scripts/conferir-encoding.cjs` sobre o resultado sai exit 0. Cole os bytes do
  fim da linha gravada mostrando terminador único.
- **T2b:** provoque um erro cuja mensagem tenha acento vindo do `node`; a linha
  gravada tem de conter a palavra correta. Prove pelos bytes, em tabela (o gate de
  publicação lê `xxd` cru como telefone — **não** cole saída de `xxd` em arquivo
  versionado).
- **T2c:** provoque o erro de `run-vigia.ps1:80` (`$configPath`) e o de `:131`
  (`$bridgeLauncher` preenchido com caminho de usuário) numa caixa; o `ERROS.md`
  resultante **não** contém caminho de máquina nem nome de usuário. Cole o conteúdo.
- **Mutações (três, uma por propriedade):** volte `Out-File -Append` → vermelho;
  tire a interceptação de encoding → vermelho; tire o saneamento → vermelho. Cole as
  três linhas de falha.
- **Trava de regressão:** a bateria fica vermelha se alguém acrescentar uma escrita
  no `ERROS.md` que não passe pela função (varredura por `Out-File.*ERROS`).

---

## T3 — o gate de encoding aprende a assinatura OEM, e o passado é backfill (D3)

**Toca:** `scripts/conferir-encoding.cjs`, `scripts/testa-conferir-encoding.sh`,
`vigias/ERROS.md`
**Depende de:** nenhuma · **Paralelizável:** sim (não colide com T1/T2)

A detecção hoje só casa a assinatura CP1252 (`conferir-encoding.cjs:134`). Acrescentar
a OEM com o **mesmo rigor mecânico**: não "contém `├`" (caractere legítimo em arte de
caixa e saída de `tree`), e sim caractere de desenho de caixa seguido de membro da
tabela fixa de round-trip, derivada da faixa `0x80`-`0xBF` do CP850. Confira se o
CP437 diverge nessa faixa; cubra os dois ou documente por que só um. Documente a
derivação no estilo do arquivo — o cabeçalho dele explica cada decisão.

**Backfill:** as linhas corrompidas do `vigias/ERROS.md` são reescritas para o texto
correto, em LF, sem BOM. **Nenhuma linha apagada** — o registro é a evidência de que o
backup falha desde 28/08. Explique no commit que foi backfill mecânico.

**Critério de pronto:**
- Fixture construída **pelos bytes** (`printf '\xe2\x94\x9c\xc3\xba'`), nunca colando
  o caractere: `bash scripts/testa-conferir-encoding.sh` a **recusa**.
- Caso de falso positivo: `├` legítimo (arte de caixa) **passa**. Cole as duas saídas.
- `node scripts/conferir-encoding.cjs` → exit 0 na árvore, com o backfill feito.
- **Mutação:** tire a assinatura OEM → o caso da fixture fica **vermelho**.
- `git diff --stat vigias/ERROS.md` mostra **0 linhas removidas**.

---

## T4 — bateria que reprova vigia agendado com `NextRunTime` vazio (D4)

**Toca:** `scripts/testa-vigias-agendados.sh` (novo)
**Depende de:** nenhuma · **Paralelizável:** sim

Só leitura (`Get-ScheduledTaskInfo` / `Get-ScheduledTask`). **Proibido** registrar,
alterar, habilitar, desabilitar ou disparar tarefa — isso é a T7, e só ela.

**Ela nasce VERMELHA**, porque `vigia-tickets-manha` e `vigia-tickets-tarde` estão de
fato mortas. Isso é o resultado certo. **Quem a torna verde é a T7.**

Caminho de pulo limpo (exit 0 dizendo que pulou), porque o plugin é público e roda em
máquina de outra gente: sem PowerShell, sem tarefa do plugin registrada, ou toggle
`vigias` desligado (`scripts/setup.cjs --ligado vigias`, como `run-vigia.ps1` faz).
Só reprova quando a tarefa **existe** e o `NextRunTime` está vazio.

Estilo das vizinhas: bash, `set -u`, contadores `ok`/`falhou`, cabeçalho explicando
por que existe com o número (20 dias mortos, desde 11/08/2026).

**Critério de pronto:**
- `bash scripts/testa-vigias-agendados.sh` → **vermelho**, nomeando as duas tarefas.
- Não é cega: `sentinela-foco`, que tem `NextRunTime`, **passa** enquanto as duas
  reprovam. Cole a saída mostrando os dois resultados na mesma execução.
- Caminho de pulo forçado em subshell (variável da própria bateria, **sem** tocar a
  config real) → exit 0 dizendo que pulou.
- `node scripts/conferir-encoding.cjs` → exit 0.

---

## T5 — o `ERROS.md` recente sobe pelo `conferir-saude` (D7)

**Toca:** `scripts/saude.cjs`
**Depende de:** T4 (mesmo arquivo de saúde, e reusa a checagem dela) · **Paralelizável:** não

Erro registrado que ninguém lê é igual a erro não registrado; este ficou cinco dias.
O `conferir-saude` passa a contar erros de vigia nas últimas N rondas e a subir uma
linha. **Não** vai para o hook de SessionStart: o payload já bate no teto de bytes, e
foi por isso que as regras 4-17 nunca chegaram a sessão nenhuma.

Encaixe a checagem da T4 aqui também, se o desenho do `saude.cjs` permitir sem
mudança estrutural. Se não permitir, **não force** — registre o achado e deixe a T4
autônoma.

**Critério de pronto:**
- `node scripts/saude.cjs` → sai uma linha com a contagem de erros de vigia recentes,
  colada. Hoje ela é diferente de zero (o `ERROS.md` tem erro de 31/08).
- Caixa com `ERROS.md` sem erro recente → a linha **não** aparece (ou aparece zerada,
  conforme o desenho). Cole as duas saídas.
- Nenhuma alteração em `hooks/` de SessionStart. `git diff --stat hooks/` vazio.

---

## T6 — "campo vazio não é campo ok" entra no acervo da regra 12 (D5)

**Toca:** `skills/rainforest-mind/references/regra-12.md`
**Depende de:** nenhuma · **Paralelizável:** sim (arquivo reservado a esta janela pelo handover)

Irmã da heurística que a Issue #142 plantou ("medição uniforme demais é suspeita").
O agendador respondeu `Ready` / `Enabled: True` / `LastTaskResult: 0` para uma tarefa
morta há 20 dias; o único sinal verdadeiro estava num campo **em branco**, e branco
lê-se como "nada de errado".

**Teto:** o arquivo está em 9.277 B contra teto de 10.500 B.

**Critério de pronto:**
- `node scripts/medir-skill.cjs` (ou a bateria que mede o teto — descubra qual é e
  use ela) → exit 0, com o tamanho novo colado.
- **Gatilho de partição:** se estourar 10.500 B, o acervo sai para
  `references/regra-12-campo-vazio.md`, como já foi feito com `regra-12-acervo.md` e
  `regra-10-portaria.md`, e a regra 12 ganha o ponteiro. Diga qual caminho foi tomado
  e cole a medida que decidiu.
- A bateria de skills/references do repositório → exit 0.

---

## T7 — reagendar as duas tarefas mortas (D6)

**Toca:** ambiente do usuário (Agendador de Tarefas do Windows). **Nenhum arquivo.**
**Depende de:** T1-T6 todas verdes · **Paralelizável:** não · **ÚLTIMA**

Regra 15: altera ambiente do usuário. **Autorizado por ele em 2026-09-01.**

Recriar o gatilho de `vigia-tickets-manha` e `vigia-tickets-tarde` **sem
`EndBoundary`**, mantendo `DaysOfWeek: 62` (seg-sex) e os horários (08:52 e 14:52).
Corrigir o espaço duplo em `-Vigia  vigia-tickets` na ação.

Antes de mexer, **grave o estado atual das duas tarefas** (export XML ou dump dos
campos) no scratchpad, para poder devolver ao que era se algo sair errado.

**Critério de pronto:**
- `Get-ScheduledTaskInfo` das cinco → **nenhum `NextRunTime` vazio**. Cole a tabela.
- O gatilho das duas → `EndBoundary` ausente. Cole os campos.
- A ação das duas → `-Vigia vigia-tickets`, espaço simples. Cole.
- `bash scripts/testa-vigias-agendados.sh` → **verde**. É a T4 virando, e é a prova de
  que ela media a coisa certa.

---

## Ordem

```
T1 -> T2   (mesmo arquivo: run-vigia.ps1)
T3         (independente)
T4 -> T5   (saude.cjs)
T6         (independente)
             todas verdes -> T7
```

Bateria completa do repositório verde antes do `revisar`. `T7` só depois do
`verificar` fechar, porque ela é a única que sai do repositório.
