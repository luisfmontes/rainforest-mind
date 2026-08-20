# Quatro entregas seguidas trouxeram bateria que passava com o defeito presente

**Data:** 2026-08-19
**Onde ocorreu:** `luisfmontes/rainforest-mind` — esteira `memoria-e-dados-do-rainforest`, tarefas 18 a 23, sete rodadas de revisão (PR #22)

> Se você só for ler um parágrafo: em **quatro** entregas distintas desta esteira — três de agente, uma minha — a bateria de regressão escrita junto com o conserto **passava contra o código defeituoso**. Medido extraindo o commit anterior para uma pasta limpa e rodando a bateria nova lá: `testa-observar-offset.sh` e `testa-memoria-migracao-atomica.sh` saíram `exit=0` contra o código que deveriam reprovar. O critério do plano ("bateria de regressão que passa nos dois lados não prova nada") existia e estava escrito na tarefa; nenhum dos agentes o executou como medição, e cada um relatou ✅.

## 1 — O padrão, e por que ele não é preguiça do agente

Quem escreve a bateria logo depois de escrever o conserto tende a testar **o que o conserto faz**, não **o que o defeito fazia**. Os quatro casos têm a mesma forma:

| Bateria | O que ela testava | O que o defeito exigia |
|---|---|---|
| `testa-observar-offset.sh` (v1) | reimplementava `substring` e `Buffer.toString` dentro do próprio teste e comparava | rodar `observar.cjs` com offset no **meio** do arquivo, com acentuação antes |
| `testa-memoria-migracao-atomica.sh` (v1) | migração completa, sem interrupção | matar o processo no meio; e o banco **já** quebrado |
| `testa-memoria-degradacao.sh` (v1) | `abrirBanco()` isolado e um `simularHook()` escrito no próprio teste | os quatro pontos de entrada reais |
| `testa-saude.sh` (teste J) | `grep` pelo nome da função no fonte | remover a checagem numa cópia e ver o alerta sumir |

O caso do `testa-observar-offset.sh` é o mais claro: a bateria provava uma verdade sobre JavaScript (que `Buffer` fatia bytes e `substring` não), não uma verdade sobre este repositório. Ela continuaria verde se alguém revertesse o conserto no dia seguinte.

Medição, com o exit code obtido sem pipe no meio:

```
CODIGO ANTIGO  testa-observar-offset.sh          => exit=0     <- deveria falhar
CODIGO ANTIGO  testa-memoria-migracao-atomica.sh => exit=0     <- deveria falhar
CODIGO ANTIGO  testa-memoria-degradacao.sh       => exit=1     <- a única correta
```

## 2 — O caso em que a bateria media outra coisa inteira

`testa-memoria-degradacao.sh` plantava o banco corrompido em `rainforest-corrompido.db`, e os quatro pontos de entrada resolvem `$RFM_ROOT/rainforest.db`. Eles caíam no ramo "banco ausente":

```
$ echo '{...}' | RFM_ROOT=$T node hooks/memoria-marca.cjs     exit=0
   18      rainforest-corrompido.db      <- nunca tocado
   90112   rainforest.db                 <- CRIADO novo pelo próprio hook
```

E todo ramo de falha era `echo "⚠"`, com `exit 0` incondicional na última linha: a bateria não tinha **como** reprovar. O commit que a introduziu afirmava na mensagem "Prova de verdade: teste detecta mudanças no hook".

## 3 — Consertar isso me custou quatro tentativas, e as quatro foram informativas

Não é um erro que se evita com atenção; é um erro que se evita com **procedimento**:

1. A guarda "o arquivo plantado ainda é ilegível?" passava — `DatabaseSync` abre sem validar. Precisa executar uma consulta.
2. O check continuava verde com a degradação removida: o `transcript_path` do payload não existia. (Depois se provou que essa não era a causa — ver seção 5.)
3. Ainda verde: `memoria-marca.cjs` degrada em **duas camadas**, e remover uma não regride comportamento nenhum.
4. Só com as duas removidas a bateria ficou vermelha: `❌ 1 falha(s)`, exit 1.

O mesmo padrão apareceu no `LADO D` da migração: a primeira versão passava porque a cópia mutada levava só `scripts/`, e o processo morria em `Cannot find module '../hooks/lib/raiz.cjs'` **antes** da migração — banco intacto lido como rollback bem-sucedido. A correção foi imprimir uma marca (`CHEGOU-AO-RENAME`) no ponto do crash e exigi-la na saída.

## 4 — O `limpar-branches.cjs` apagou a `main` local

Rodando a limpeza do estágio `fechar` com `--base memoria-e-dados-do-rainforest` (a base correta, já que o trabalho não chegou à `main`), a branch `main` foi classificada como já contida na base e removida junto com as 11 branches de agente. Nada se perdeu — `origin/main` estava intacta em `d52f5a4` e um `git branch main origin/main` recriou —, mas o `git log main..HEAD` do passo seguinte falhou com `unknown revision`, e num repositório sem a branch padrão no remoto isso seria pior.

A branch padrão do repositório (`origin/HEAD`) não deveria entrar na remoção, nem quando `--base` aponta para outra ref.

## 5 — Duas vezes o erro foi meu, e do mesmo tipo

**Exit code através de pipe.** Medi `bash script.sh ... | tail -2; echo $?` e li o status do `tail`. A skill `verificar` nomeia exatamente esse cuidado; eu li a skill e errei mesmo assim, na primeira medição.

**Causa atribuída sem medir.** Escrevi no comentário do teste que "sem o transcrito o hook faz early-return e nunca chega a abrir o banco". A 7ª revisão derrubou: `resolverTranscrito` (`memoria-marca.cjs:57`) devolve `evento.transcript_path` sem checar `existsSync`, e o resultado é idêntico com o arquivo presente ou ausente. O comentário estava mais errado que o código.

## 6 — Uma bateria que pendura o terminal custou dez minutos

`testa-memoria-degradacao.sh` (v2) invocava os hooks sem alimentar stdin, e eles leem o payload dali:

```
$ timeout 20 node hooks/memoria-marca.cjs >/dev/null 2>&1
exit=124        (travado, esperando entrada)
```

Passou para quem a escreveu porque rodou com `</dev/null`. Rodando a suíte no terminal, ela pendura sem sinal nenhum de que está esperando.

## O que deu certo

- **Dividir a revisão por superfície de risco.** A 4ª rodada usou três revisores com recortes disjuntos (banco/migração, hooks/observador, baterias/creep) e achou **três críticos** que as três rodadas anteriores, com revisor único, não alcançaram — incluindo o offset em bytes, que matava a captura em qualquer sessão em português.
- **A regra 11 pagou duas vezes.** Os dois worktrees de agente nasceram na base errada (`d52f5a4` em vez do hash do briefing). O tester conferiu, parou sem commitar e reportou; o segundo despacho já trouxe o `git merge --ff-only <hash>` como procedimento, e ele se corrigiu sozinho.
- **`conferir-entrega.cjs` aprovou as três entregas** com os avisos certos (base ancestral e não pai direto, HEAD do principal avançado), sem nenhum falso verde.
- **Guarda contra mutação que não casa.** No teste J escrevi "se o `sed` não casar com o fonte, FALHA" — e ela pegou **meu próprio** alvo errado na primeira execução. Guarda que protege quem a escreveu é o formato certo.
- **Revisor que declara lacuna em vez de fingir cobertura.** Um deles não mutou o `RFM_ROOT` porque a cadeia de resolução cai em `~/.rainforest` se a variável for neutralizada, e o risco à memória real não valia o achado. Abortou antes de executar e nomeou a lacuna.

## Propostas

**P1 — O briefing de conserto passa a exigir a medição nos dois lados, com o comando pronto.** Não basta pedir "prova por mutação": o texto tem de trazer `git archive <hash-anterior> | tar -x -C <pasta>`, `cp` da bateria para lá, e `bash script.sh >/dev/null 2>&1 </dev/null; echo $?` — com a frase "bateria que passa nos dois lados não fecha o item". **Destino: `agents/executor.md` e `agents/tester.md`**, na seção de entrega. Pendente.

**P2 — Bateria nova que exercita hook nasce com stdin e teto de tempo.** `</dev/null` ou payload pipado, mais `timeout`, viram parte do padrão documentado de bateria. **Destino: `agents/tester.md`** e o comentário-modelo das baterias existentes. Pendente.

**P3 — `limpar-branches.cjs` nunca remove a branch padrão.** Excluir `origin/HEAD` da classificação, independente de `--base`. **Destino: Issue no repo do plugin, com o cenário desta sessão colado.** Pendente.

**P4 — A prova de eficácia entra no estágio `verificar`, não só no `revisar`.** Hoje o `verificar` roda o critério do plano; quando o critério **é** uma bateria, rodar só ela mede o instrumento por dentro. A régua adicional: para toda bateria criada na esteira em curso, medir também contra a base do trabalho. **Destino: `skills/verificar/SKILL.md`.** Pendente.

**P5 — Registrar no padrão de bateria que o teste declara o que NÃO prova.** Dois arquivos desta esteira ganharam isso e o revisor confirmou a honestidade da declaração (`LADO D` da migração, camadas de degradação). É barato e evita que alguém confie no teste pelo motivo errado. **Destino: `agents/tester.md`.** Pendente.
