# Plano: conta-reserva-avisa — o vigia não trava em silêncio, a pasta manual volta e o problema chega à sessão

Design: docs/rainforest/design/conta-reserva-avisa.md

Base: `71912254948915dd7853e382932e4f438983ff6f` (branch `fluxo/conta-reserva-avisa`). Issue #693.

## Achados que mudam o desenho (ler antes das tarefas)

Cada item abaixo é um fato lido no código da base, e o plano já assume o remédio. Os itens 1 a 4, 9 e 10 corrigem o texto do design sem mudar nenhuma decisão `D<n>`; se o usuário discordar de algum, o fluxo volta ao `brainstorm` para a D afetada (regra 16).

1. **A volta do vigia grava `voltar`, não `trocar`** (CONFIRMADO: `scripts/conta.cjs:988` passa `tipo: 'voltar'` ao `aplicarTroca`, que o grava como veio, e `scripts/testa-conta.sh:363` exige `"tipo":"voltar"`). A D3 diz "grava o evento `trocar` como hoje" e a D5 lista só `trocar` e `reconciliado` como resolvedores. Só a troca manual (`/conta`) grava `trocar` ao voltar. Assumido: o hook trata `trocar`, `voltar` e `reconciliado` da mesma pasta como resolvedores de `manual_no_limite` e `uso_ilegivel`; sem o `voltar`, o aviso de limite ficaria aberto por 7 dias depois de a pasta voltar.
2. **Não existe evento `renovado`** (CONFIRMADO: `grep "renovado" scripts/conta.cjs` só acha comentários; os tipos gravados são `trocar`, `voltar`, `falhou`, `renovacao_falhou`, `manual_no_limite`, `credencial_duplicada`, `identidade_divergente`, `reconciliado`). A D5 manda "o mesmo critério de `falhasDeRenovacao`", e esse critério (`scripts/conta.cjs:595-613`) é o `expiresAt` do arquivo do login: falha aberta enquanto o login existe e vence em menos de 1 h. Assumido: vale o critério do código, sem evento novo; renovação que deu certo empurra o `expiresAt` e a falha some sozinha. Consequência: o hook lê `expiresAt` de `reserva-*.json` e `estacionado-*.json` (só esse campo, nunca token).
3. **A D5 não diz o que resolve `vigia_falhou` nem `pasta_sem_credencial`.** Decisão técnica, sem impacto de produto: (a) `vigia_falhou` fecha quando o `mtime` de `<dados>/contas/vigia-ok` (a marca que a própria D2 cria) é mais novo que o evento; (b) `pasta_sem_credencial` fecha com um evento novo `pasta_com_credencial`, gravado pelo vigia na primeira rodada em que a pasta volta a ter credencial depois de um `pasta_sem_credencial` em aberto. Esse mesmo par de eventos é o que a D1 precisa para "só grava de novo depois de uma rodada em que a pasta teve credencial". O mod não faz toast para tipo novo (CONFIRMADO: `frase()` em `hooks/conta-puro.mjs` termina em `return ''` e `hooks/conta.ts:60-61` só notifica texto não vazio).
4. **D3 sem login estacionado da casa continua `avisar`** (INFERIDO, e é o que o caso `#584 ML3` de `scripts/testa-conta.sh:1080-1088` já exige: `manual_no_limite` com `causa: sem_login_guardado` manda o usuário refazer o `/login`). A D3 só descreve folga e dado de uso; sem estacionado não há como devolver, e `esperar` calaria o aviso. Com estacionado e vida curta, vale a D3: `esperar` pela mesma `checarVida`.
5. **Três casos existentes de `scripts/testa-conta-decidir.cjs` invertem com a D3** (CONFIRMADO pela fixture: a team está em 15/53, ou 10/10 no terceiro, com `estacionado` presente, ou seja, casa com folga): "pasta manual com a conta em uso a 100% na semana devolve avisar" (linha 199), "pasta manual com os dois limites passados avisa o que reseta por último" (213) e "pasta manual no limite nunca recebe trocar nem voltar, nem depois do reset" (220). A tarefa 2 os reescreve (os dois primeiros ganham uma casa sem folga, o terceiro vira o caso positivo da D3). O bloco `#584` de `scripts/testa-conta.sh` continua `avisar`: lá a `reserva-team` está vencida, então a conta de casa fica sem dado de uso (INFERIDO; a tarefa 2 roda a bateria inteira para confirmar). `hooks/testa-mod-conta.cjs` não é afetado pelo vigia: ele chama `frase()` direto com um `manual_no_limite` montado à mão, não gera o evento pelo vigia (CONFIRMADO: linhas 239-245); só as asserções de texto da tarefa 10 mudam.
6. **Textos que a D3 torna falsos, e a tarefa de cada um:** `scripts/lib/conta-decidir.cjs` (cabeçalho, linhas 1-45) na tarefa 2; `scripts/conta.cjs:828` (`troca manual (sem volta automática)`) na tarefa 8; `README.md:311` e `:338` e `commands/conta.md:19` na tarefa 9. `hooks/conta-puro.mjs:41` e `:67` ("não volta sozinha", as duas frases do toast) na tarefa 10: o toast continua sem tipo novo, mas as duas frases que a D3 deixa falsas são corrigidas.
7. **Hook novo entra no fim da abertura** (CONFIRMADO: `scripts/testa-memoria-somente-leitura.sh:74-78` e `scripts/exporta-hooks-sessao-start.cjs` mapeiam os hooks de `SessionStart` por posição; `hooks/testa-memoria-recuperacao.sh:36` usa `grep -A 20`). Por isso o registro é um grupo novo ao fim de `SessionStart` (sem `matcher`) e uma entrada ao fim do grupo existente de `UserPromptSubmit`: nenhum índice existente muda.
8. **Risco aceito pelo design, dito aqui para o usuário saber:** a chave "já visto" não leva o `em` do evento, então uma recorrência do mesmo problema dentro da mesma sessão não é anunciada de novo; e `uso_ilegivel` fica aberto até um `trocar`/`voltar`/`reconciliado` da pasta, mesmo que o dado de uso volte antes (a D4 zera só o `semUsoDesde`). Ambos têm teto de 7 dias.
9. **Pasta renomeada deixaria o `pasta_sem_credencial` aberto por 7 dias** (CONFIRMADO: `pastasAtivas()` em `scripts/conta.cjs:64` só inclui a pasta pessoal se ela existe; renomear `~/.claude-personal`, o remédio que o próprio aviso recomenda, tira a pasta do laço, e nenhuma rodada grava mais evento dela). Decisão técnica dentro da D1: em toda rodada, para a pasta cujo último evento de credencial é `pasta_sem_credencial` e que não está mais em `pastasAtivas()`, o vigia grava `pasta_com_credencial` com o motivo `pasta saiu de uso` (tarefa 1, caso (d1-5)).
10. **`vigia-ok` só é tocado quando a rodada chegou a `decidir`** (CONFIRMADO: `vigiar` tem retornos antecipados sem decisão: `outra rodada em curso`, `troca automática desligada`, `o mesmo login está em dois arquivos`). A D2 diz "ao fim de toda rodada sem exceção"; um retorno antecipado não prova que o vigia voltou a conseguir decidir, e fecharia o `vigia_falhou` cedo demais. Decisão técnica: `vigiarRodada` devolve `{ codigo, decidiu }` e só `decidiu: true` marca o arquivo (tarefa 3, caso (d2-5)).

Decidido no modo autônomo (2026-11-12): corrigir as duas frases do toast, tarefa 10.

## O que não pode quebrar
- `bash scripts/testa-conta.sh` continua verde (`ok: 69   falhou: 0` na base, 89 s medidos em 2026-11-12), inclusive todo o bloco `#584`.
- `node scripts/testa-conta-decidir.cjs` (36 ok na base) e `node hooks/testa-mod-conta.cjs` (32 ok na base) continuam verdes, salvo os três casos reescritos na tarefa 2 (`decidir`) e a asserção da linha 169 do `testa-mod-conta.cjs`, reescrita na tarefa 10.
- `bash scripts/testa-conta-uma-pasta.sh`, `scripts/testa-conta-preparar.sh`, `scripts/testa-conta-unificar.sh`, `scripts/testa-conta-agendar.sh` e `scripts/testa-conta-mover.sh` continuam verdes (rodar as cinco ao fim das tarefas 1, 3, 6, 7 e 8, que mexem em `conta.cjs`).
- `status` e os outros subcomandos não mudam (D1), com uma exceção declarada: o texto da linha de pasta manual (tarefa 8).
- Nenhuma credencial, token ou trecho de arquivo de credencial entra em evento, em saída do vigia ou em `additionalContext` (`msgSegura` continua a única porta de mensagem de erro).
- O hook novo nunca derruba a sessão: exit 0 em qualquer entrada, sem rede, sem trava (`vigia.lock`) e sem `spawn`.
- `node scripts/conferir-caixas.cjs` não passa de `224 bateria(s), 128 achado(s)` (base) e `node scripts/conferir-categoria.cjs` fecha com `CONFERIDO` (68 peças ao fim da tarefa 5).
- A ordem dos hooks de `SessionStart` já registrados não muda.

## Tarefas

### 1. D1: pasta sem credencial fica fora da decisão e vira evento [tipo: implementar]
atende: D1
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-vigia-avisa.sh`
depende de: nenhuma
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (!credDaPasta(c, P)) { // D1 (conta-reserva-avisa)`
  para: `if (false) { // D1 (conta-reserva-avisa)`
  bateria: `bash scripts/testa-conta-vigia-avisa.sh`
  fixture: `testa-conta-vigia-avisa.sh, casos (d1-1) a (d1-4)`
prova: `bash scripts/testa-conta-vigia-avisa.sh`
pronto quando: com um home temporário no formato real (a fixture `semear.cjs` + `ajustar.cjs trocado` de `scripts/testa-conta.sh`, servidor falso `scripts/fixtures/conta/servidor.cjs`), a pasta `trabalho` na conta pessoal com `manual: true` e `travouPor: null`, a pessoal a 100% na semana (`uso7: 100` nos tokens da pessoal) e `.claude-personal` existindo SEM `.credentials.json`, `node scripts/conta.cjs vigiar` sai 0 e imprime `avisar trabalho: seven_day de pessoal em 100%` (a decisão da pasta que tem credencial); `eventos.jsonl` ganha exatamente um `{"tipo":"pasta_sem_credencial","pasta":"pessoal"...}` em duas rodadas seguidas e nenhum `vigia_falhou`; depois de o arquivo `.credentials.json` da pessoal voltar, a rodada seguinte grava um `pasta_com_credencial` da pessoal (e nenhum outro na rodada depois dela); removido de novo, a rodada grava o segundo `pasta_sem_credencial`; com a pasta `.claude-personal` renomeada para `.claude-personal.stub-teste` (sai de `pastasAtivas`) e um `pasta_sem_credencial` em aberto, a rodada seguinte grava um `pasta_com_credencial` da pessoal com o motivo `pasta saiu de uso`, e a rodada depois dela não grava outro; `status` continua imprimindo a linha `pasta pessoal: sem credencial` — provado por `bash scripts/testa-conta-vigia-avisa.sh` terminando em `ok: 14   falhou: 0` com exit 0, e pela mutação acima deixando (d1-1), (d1-2) e (d1-3) vermelhos (a pasta sem credencial volta a derrubar a rodada: exit 1 e `erro: pasta pessoal sem credencial`).

Acoplamento com a tarefa 2 (aviso do `conferir-fluxo camadas`: `conta.cjs` importa `conta-decidir.cjs`, e a tarefa 2 muda `decidir`): a fixture de (d1-1) deixa a conta de casa sem dado de uso (a `reserva-team` vencida que o `ajustar.cjs trocado` já produz), então `avisar` vale antes e depois da tarefa 2. Não ponha a team legível nesta bateria. O estado do `estacionado-trabalho` (o `ajustar.cjs trocado` o deixa vencido) é irrelevante para os casos (d1-*): pasta `manual: true` com a conta de casa sem dado nunca chega a `checarVida`.

Bateria nova `scripts/testa-conta-vigia-avisa.sh` (as tarefas 3, 6 e 8 acrescentam casos nela): primeira linha `#!/bin/bash`, `set -euo pipefail`, `cd "$(dirname "$0")/.."`, `trap` que apaga o diretório temporário e mata o servidor falso pelo PID. Copia de `scripts/testa-conta.sh` só o que usa: `win`, `afirma`, `contem`, `semear.cjs` (os dois modos), `ler.cjs`, `derivar.cjs`, a parte `trocado` de `ajustar.cjs`, `iniciar_servidor`, `novo_caso` e `cli` (é a mesma lista de variáveis `RFM_TEST=1`, `RFM_CONTA_PASTA_TRABALHO`, `RFM_CONTA_PASTA_PESSOAL`, `RFM_CONTA_CLAUDE_JSON`, `RFM_CONTA_DADOS`, `RFM_CONTA_API`). Roda contra os scripts do próprio repositório, sem copiá-los para a caixa (`conferir-caixas` não pode ganhar achado). Termina com `echo "ok: $OK   falhou: $FALHOU"` e `exit 1` se `FALHOU` > 0 (é o formato que a catraca de mutação lê).

Forma prescrita: em `vigiar`, trocar a linha `for (const P of pastasAtivas()) pastas[P] = infoPasta(c, estado, P);` por

```
    for (const P of pastasAtivas()) {
      if (!credDaPasta(c, P)) { // D1 (conta-reserva-avisa)
        avisarPastaSemCredencial(c, P);
        continue;
      }
      registrarCredencialVoltou(c, P);
      pastas[P] = infoPasta(c, estado, P);
    }
```

e definir, acima de `vigiar`, três funções: `ultimoDaCredencial(c, P)` (o último evento de `lerEventos(c)` com `pasta === P` e `tipo` igual a `pasta_sem_credencial` ou `pasta_com_credencial`, ou `undefined`), `avisarPastaSemCredencial(c, P)` (grava `{ tipo: 'pasta_sem_credencial', pasta: P, motivo: 'sem .credentials.json', manual: false }` por `registrarEvento` só se o último não for `pasta_sem_credencial`) e `registrarCredencialVoltou(c, P)` (grava `{ tipo: 'pasta_com_credencial', pasta: P, motivo: '.credentials.json voltou', manual: false }` só se o último for `pasta_sem_credencial`). Depois do laço (antes de `const usos`), chamar `registrarPastaSaiuDeUso(c)`: para cada `P` de `Object.keys(CONTA_CLI)` que não está em `pastasAtivas()` e cujo `ultimoDaCredencial(c, P)` é `pasta_sem_credencial`, grava `{ tipo: 'pasta_com_credencial', pasta: P, motivo: 'pasta saiu de uso', manual: false }`. Nenhum caso de teste pode afirmar sobre o texto do fonte. `credDaPasta` que lança por JSON inválido NÃO é "sem credencial": segue lançando e é da tarefa 3.

Casos (todos com a fixture acima, `automatico: sim`):
| caso | o que mede |
|---|---|
| d1-1 | `vigiar` com a pessoal sem credencial: exit 0 e saída com `avisar trabalho: seven_day de pessoal em 100%` (2 afirmações) |
| d1-2 | o mesmo, duas rodadas: um só `pasta_sem_credencial`, com `pasta: pessoal`, e zero `vigia_falhou` (3) |
| d1-3 | a pessoal ganha o `.credentials.json` de volta: a rodada seguinte grava um `pasta_com_credencial`, uma terceira não grava outro, e o `pasta_sem_credencial` continua um só (3) |
| d1-4 | a credencial some de novo: o segundo `pasta_sem_credencial`, a rodada sai 0, e `status` imprime `pasta pessoal: sem credencial` (3) |
| d1-5 | com um `pasta_sem_credencial` da pessoal em aberto, `.claude-personal` é renomeada para `.claude-personal.stub-teste`: a rodada sai 0, grava um `pasta_com_credencial` da pessoal com o motivo `pasta saiu de uso`, e a rodada seguinte não grava outro (3) |


### 2. D3: pasta manual no limite volta quando a casa tem folga [tipo: implementar]
atende: D3
arquivos: `scripts/lib/conta-decidir.cjs`, `scripts/testa-conta-decidir.cjs`, `scripts/testa-conta.sh`
depende de: nenhuma
mutacao:
  arquivo: `scripts/lib/conta-decidir.cjs`
  de: `const folga = dadosCompletos(casaUso) && casaUso.five_hour.utilization < config.destinoMax5h && casaUso.seven_day.utilization < config.destinoMaxSemana; // D3 (conta-reserva-avisa)`
  para: `const folga = true; // D3 (conta-reserva-avisa)`
  bateria: `node scripts/testa-conta-decidir.cjs`
  fixture: `testa-conta-decidir.cjs, casos (d3-2) e (d3-3)`
prova: `node -e 'const {decidir}=require("./scripts/lib/conta-decidir.cjs");const V=Date.now()+8*3600e3;const j=(u)=>({utilization:u,resets_at:"2030-01-01T00:00:00Z"});const r=decidir({pastas:{trabalho:{casa:"team",conta:"pessoal",manual:true,travouPor:null,expiresAt:V,estacionado:{expiresAt:V}}},usos:{pessoal:{five_hour:j(10),seven_day:j(100)},team:{five_hour:j(10),seven_day:j(10)}},reservas:{},config:{trocarEm:97,destinoMax5h:60,destinoMaxSemana:85},agora:Date.now()});process.exit(r.length===1&&r[0].tipo==="voltar"?0:1)'`
pronto quando: com a entrada que o vigia monta (pasta `trabalho` com `casa: team`, `conta: pessoal`, `manual: true`, `travouPor: null`, `estacionado` vivo; usos da pessoal em 100% na semana), `decidir` devolve `voltar` da pasta `trabalho` para `team` quando a team está abaixo de `destinoMax5h` e de `destinoMaxSemana`; devolve `avisar` (como na base) com a team a 90% na semana, sem dado de uso da team ou sem `estacionado`; devolve `esperar` com o `estacionado` a 29 min de vencer; e, num home temporário com o servidor falso (pasta `trabalho` na conta pessoal, `manual: true`, `estacionado-trabalho` e `reserva-team` vivos, team a 10%/10%, pessoal a 100% na semana), `node scripts/conta.cjs vigiar` sai 0 imprimindo `voltar trabalho: pessoal -> team`, o `estado.json` fica com `pastas.trabalho.conta` = `team` e `manual` = `false`, o `claudeAiOauth.refreshToken` do `.credentials.json` da pasta volta ao do `estacionado-trabalho.json` lido antes da rodada e o log ganha um `"tipo":"voltar"` e nenhum `manual_no_limite` — provado por `node scripts/testa-conta-decidir.cjs` terminando em `40 ok, 0 falha(s)` e `bash scripts/testa-conta.sh` terminando em `ok: 74   falhou: 0`, e pela mutação acima deixando (d3-2) e (d3-3) vermelhos (sem a conferência de folga, a pasta voltaria a uma conta cheia ou sem dado).

Forma prescrita em `scripts/lib/conta-decidir.cjs`: em `decidir`, dentro de `if (pasta.manual) {`, antes de chamar `avisoManual`, chamar uma função nova `voltaManual(nome, pasta, usos, config, agoraMs)`; se ela devolver uma ação, empurra-a e `continue`; se devolver `null`, segue o `avisoManual` de hoje. `voltaManual` devolve `null` salvo quando, nesta ordem: a pasta está fora de casa; `dadosCompletos(usos[pasta.conta])` e algum limite com `utilization >= config.trocarEm` (o primeiro de `LIMITES`); a linha de `folga` da mutação (`casaUso` é `usos[pasta.casa]`, e a linha é uma expressão só, sem ramo) é verdadeira; `pasta.estacionado` existe. Aí devolve `checarVida(nome, pasta.casa, pasta, pasta.estacionado.expiresAt, agoraMs, 'voltar', motivo)` com `motivo` no formato `<limite> de <conta> em <n>% (>= <trocarEm>)` (o mesmo de `decidirEmCasa`, que o `motivoLegivel` do mod reconhece). Atualizar o cabeçalho do arquivo (regras de manual): "pasta manual fora de casa com a conta em uso no limite e a conta de casa com folga volta (D3 de conta-reserva-avisa); sem folga, sem dado da casa ou sem estacionado, avisa". Nenhum caso de teste pode afirmar sobre o texto do fonte.

Casos em `scripts/testa-conta-decidir.cjs` (os três existentes mudam; nomes dos novos entre parênteses):
| caso | mudança |
|---|---|
| linha 199 "pasta manual com a conta em uso a 100% na semana devolve avisar" | a fixture ganha casa sem folga (`deriva("team","seven_day","utilization",90, ...)`); segue esperando `avisar` |
| linha 213 "pasta manual com os dois limites passados avisa o que reseta por último" | idem |
| linha 220 "pasta manual no limite nunca recebe trocar nem voltar, nem depois do reset" | reescrito como (d3-1): team 10/10, estacionado vivo, pessoal a 100% na semana: uma ação `voltar`, `pasta: trabalho`, `conta: team`, motivo casando `/seven_day de pessoal em 100%/` |
| linha 183 "pasta trocada na mão não volta sozinha mesmo depois do reset" | renomeado para "pasta manual abaixo do limite não volta sozinha mesmo depois do reset" (a fixture não muda: pessoal a 5% e 15%, abaixo do `trocarEm`); o título antigo passa a mentir com a D3 |
| (d3-2) novo | team a 90% na semana: `avisar`, nunca `voltar` |
| (d3-3) novo | `usos.team` ausente: `avisar` |
| (d3-4) novo | sem `estacionado`: `avisar` |
| (d3-5) novo | `estacionado.expiresAt` a 29 min: `esperar`, e nenhuma ação `avisar` |

Caso de integração em `scripts/testa-conta.sh` (nova seção `#693 D3` logo depois do bloco `#584`, com `novo_caso d3 sim`, `ajustar.cjs trocado`, `manual = true` pelo mesmo `node -e` do bloco `#584`, e, depois do `ajustar`, `expiresAt` de `estacionado-trabalho.json` e `reserva-team.json` em `4102444800000`; mapa derivado com `uso7: 100` nos dois tokens da pessoal e `uso5: 10`, `uso7: 10` nos dois da team): 5 afirmações novas, (d3-i1) `vigiar` sai 0 e a saída contém `voltar trabalho: pessoal -> team`, (d3-i2) `estado.json` com `pastas.trabalho.conta` = `team`, (d3-i3) `pastas.trabalho.manual` = `false`, (d3-i4) o `claudeAiOauth.refreshToken` do `.credentials.json` da pasta `trabalho` é igual ao do `estacionado-trabalho.json` lido por `ler` antes da rodada (padrão do `caso_k` de `testa-conta.sh`; o hash do arquivo inteiro nunca bate, porque o `ajustar trocado` grava no estacionado só o `claudeAiOauth`, sem `mcpOAuth` nem `trustedDeviceToken`), (d3-i5) `"tipo":"voltar"` presente e zero `manual_no_limite` no log. 36 + 4 casos novos = 40 no `testa-conta-decidir.cjs`; 69 + 5 = 74 no `testa-conta.sh`.

### 3. D2: rodada que aborta vira evento [tipo: implementar]
atende: D2
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-vigia-avisa.sh`, `scripts/testa-conta.sh`
depende de: 1
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `const repetida = ultima !== undefined && ultima.motivo === motivo && !(okEm > ultima.em); // D2 (conta-reserva-avisa)`
  para: `const repetida = false; // D2 (conta-reserva-avisa)`
  bateria: `bash scripts/testa-conta-vigia-avisa.sh`
  fixture: `testa-conta-vigia-avisa.sh, caso (d2-1)`
prova: `bash scripts/testa-conta-vigia-avisa.sh`
pronto quando: com um home temporário no formato real e o `estado.json` com JSON inválido (`{`), duas rodadas seguidas de `node scripts/conta.cjs vigiar` saem 1, escrevem `erro: JSON inválido` no stderr (como hoje) e o `eventos.jsonl` ganha exatamente um `{"tipo":"vigia_falhou","motivo":"JSON inválido em estado.json"...}`; com o `estado.json` válido e o `.credentials.json` da pasta `trabalho` com JSON inválido, a rodada grava um segundo `vigia_falhou` com o motivo `JSON inválido em .credentials.json`; com tudo válido, a rodada sai 0 e cria o arquivo `<dados>/contas/vigia-ok`; com o mesmo erro de novo depois dessa rodada, grava um terceiro; com o `estado.json` válido mas `automatico: false`, a rodada sai 0 com `troca automática desligada` e NÃO cria nem toca `vigia-ok` (só a rodada que chegou a `decidir` o marca); nenhum desses eventos nem a saída contém o texto do arquivo corrompido (`falso-segredo-xyz` colocado dentro dele) — provado por `bash scripts/testa-conta-vigia-avisa.sh` terminando em `ok: 26   falhou: 0` com exit 0 (14 da tarefa 1 + 12 de (d2-*), medido na integração), por `bash scripts/testa-conta.sh` terminando em `ok: 74   falhou: 0` (a asserção "arquivo corrompido: a trava é solta e nada é movido" passa a aceitar o `vigia_falhou` da D2 e nenhum outro evento), e pela mutação acima deixando (d2-1) vermelho (a rodada com o mesmo erro passaria a gravar um evento por minuto).

Forma prescrita: renomear o `async function vigiar(c)` atual para `vigiarRodada(c)` (corpo intacto, exceto o que a tarefa 1 já fez) e criar acima dele

```
const VIGIA_OK = 'vigia-ok';
async function vigiar(c) {
  try {
    const { codigo, decidiu } = await vigiarRodada(c);
    if (decidiu) marcarVigiaOk(c);
    return codigo;
  } catch (e) {
    registrarVigiaFalhou(c, e);
    throw e;
  }
}
```

Em `vigiarRodada`, todo `return sair(...)` antecipado (`outra rodada em curso`, `troca automática desligada`, `o mesmo login está em dois arquivos`) vira `return { codigo: sair(...), decidiu: false }`, e só o último (o de `rodada concluída` / `alguma ação não foi feita`, depois de `decidir` e do laço de ações) vira `return { codigo: sair(...), decidiu: true }`. Além disso há duas funções novas: `marcarVigiaOk(c)` (grava `String(Date.now())` em `path.join(c.contas, VIGIA_OK)`, dentro de `try/catch` que engole o erro) e `registrarVigiaFalhou(c, e)` (tudo dentro de `try/catch` que engole o erro, para nunca trocar a exceção original): `motivo = msgSegura(e)`; `ultima` = o último evento `vigia_falhou` de `lerEventos(c)`; `okEm` = `mtimeMs` do arquivo `vigia-ok` (0 se ausente); a linha da mutação decide se repete; se não repete, `registrarEvento(c, { tipo: 'vigia_falhou', motivo, manual: false })`. `main().catch` não muda: o `throw e` chega a ele, que escreve `erro: ...` no stderr e põe `exitCode = 1`. Nenhum caso de teste pode afirmar sobre o texto do fonte.

Casos (home temporário como na tarefa 1, `automatico: sim`):
| caso | o que mede |
|---|---|
| d2-1 | `estado.json` = `{`: duas rodadas, ambas exit 1, um só `vigia_falhou` com o motivo `JSON inválido em estado.json` (3 afirmações) |
| d2-2 | o stderr da rodada tem `erro: JSON inválido` e o evento não tem o texto do arquivo (`falso-segredo-xyz`) (2) |
| d2-3 | `estado.json` restaurado e `.credentials.json` da `trabalho` corrompido: segundo `vigia_falhou` (motivo diferente); depois, com tudo válido, a rodada sai 0 e `vigia-ok` existe; corrompido de novo: terceiro `vigia_falhou` (4) |
| d2-4 | antes de qualquer rodada completa `vigia-ok` não existe, e depois de uma rodada que lançou continua não existindo (2) |
| d2-5 | `automatico: false` com `estado.json` válido, depois de um `vigia_falhou`: a rodada sai 0 com `troca automática desligada` e `vigia-ok` continua inexistente; com `automatico: true`, a rodada seguinte o cria (2) |

### 4. D5: lib de avisos de conta (leitura do log, problemas abertos, seção) [tipo: implementar]
atende: D5, D6
arquivos: `scripts/lib/conta-avisos.cjs`, `scripts/testa-conta-avisos.cjs`
depende de: nenhuma
busca:
- repo | grep -n falhasDeRenovacao scripts/conta.cjs | a regra de falha de renovação aberta mora presa ao contexto do conta.cjs (c.eventos, lerJson); a lib a recebe com leitores injetados
- repo | grep -rn eventos.jsonl hooks/lib scripts/lib | nada: nenhuma lib lê o log de eventos de conta; `hooks/lib/contas-claude.cjs` só resolve a pasta de config pela sessão e `hooks/lib/poda-dados.cjs` não cita contas
desfecho: estender
mutacao:
  arquivo: `scripts/lib/conta-avisos.cjs`
  de: `const precisaRenovar = (exp, agora) => Number.isFinite(exp) && exp - agora < RENOVAR_ANTES_MS; // D5 (conta-reserva-avisa)`
  para: `const precisaRenovar = () => true; // D5 (conta-reserva-avisa)`
  bateria: `node scripts/testa-conta-avisos.cjs`
  fixture: `testa-conta-avisos.cjs, caso (a5) renovacao_falhou some quando o login foi renovado`
prova: `node scripts/testa-conta-avisos.cjs`
pronto quando: com linhas de `eventos.jsonl` no formato que `registrarEvento` grava (um objeto por linha, campos `em`, `tipo`, `pasta`, `de`, `para`, `motivo`, `manual`, `causa`) e leitores injetados para o `expiresAt` dos logins e o `mtime` de `vigia-ok`, `problemasAbertos` devolve a lista ordenada com um item por chave (`vigia_falhou`, `pasta_sem_credencial:<pasta>`, `renovacao_falhou:<login>`, `uso_ilegivel:<pasta>`, `manual_no_limite:<pasta>`) e `montarSecao` devolve o texto da D6 — provado por `node scripts/testa-conta-avisos.cjs` terminando em `30 ok, 0 falha(s)`, e pela mutação acima deixando (a5) vermelho (login já renovado continuaria como falha aberta). Superfície humana: cada linha da seção diz o sujeito (a pasta ou o login) e o comando que resolve, e os casos (a9-1) a (a9-4) falham se um dos dois sumir.

Exports de `scripts/lib/conta-avisos.cjs` (módulo CommonJS, só `node:fs`, `node:os`, `node:path` e `../../hooks/lib/raiz.cjs`; sem `child_process`, sem rede):

- `RENOVAR_ANTES_MS` (1 h, o mesmo valor de `scripts/conta.cjs:37`), `JANELA_DIAS` (7).
- `dadosDir({ env, home, plugin })`: `env.RFM_CONTA_DADOS` se definida; senão `resolverRaiz({ cwd: home, plugin }).raiz` (é exatamente o `dadosDir` de `scripts/conta.cjs:78-86`); devolve `null` se não houver raiz.
- `lerEventosArq(arq)`: só os objetos com `em` numérico, na ordem do arquivo; linha que não é JSON ou não é objeto é pulada; `ENOENT` devolve `[]`; outro erro lança.
- `falhasDeRenovacao(eventos, expiraEm, agora)`: a última falha de cada login (motivo no formato `<login>: <erro>`, regex `^([\w-]+): (.*)$` como em `conta.cjs:598-603`), mantida só se `precisaRenovar(expiraEm(login), agora)`; devolve `[{ nome, em, erro }]`. `expiraEm(nome)` devolve `expiresAt` em ms ou `null` (arquivo ausente, ilegível ou sem login).
- `problemasAbertos(eventos, { agora, expiraEm, vigiaOkEm })`: só eventos com `agora - em <= JANELA_DIAS` dias; ignora `pasta` fora de `trabalho`/`pessoal`, `de`/`para` fora de `team`/`pessoal` e `nome` de login com mais de 20 caracteres (o maior real é `estacionado-trabalho`, com 20); devolve `[{ chave, tipo, em, pasta, nome, motivo, causa, de, para }]` com um item por chave, na ordem `vigia_falhou`, `pasta_sem_credencial`, `renovacao_falhou`, `uso_ilegivel`, `manual_no_limite` (e, dentro do tipo, o mais recente primeiro). Abertura: `vigia_falhou` enquanto `vigiaOkEm` for `null` ou `<= em`; `pasta_sem_credencial` enquanto o último evento da pasta entre ele e `pasta_com_credencial` for o primeiro; `uso_ilegivel` e `manual_no_limite` enquanto não houver, depois do evento, `trocar`, `voltar` ou `reconciliado` da mesma pasta; `renovacao_falhou` pela `falhasDeRenovacao`.
- `montarSecao(problemas)`: `''` se vazio; senão `## Conta (regra 14)` e, em linhas seguintes, no máximo 5 linhas de problema (o excedente vira uma linha final `... e mais N: node scripts/conta.cjs status`, com N = total menos 5). Cada linha tem no máximo 200 caracteres e leva o COMANDO ANTES do trecho de log: o texto fixo (com o trecho vazio, `(log: "")` incluído) vem primeiro, e o trecho livre do log (`motivo`, `erro`) recebe o orçamento que sobra, `200 − comprimento do texto fixo`, limitado ao intervalo de 20 a 80 caracteres e cortado com `…` (contado no orçamento); o `slice` de 200 caracteres no fim da linha é só rede de segurança e não pode ser o que decide. Medido na base do plano: o texto fixo tem 169 caracteres em `vigia_falhou` e em `renovacao_falhou` de `reserva-team` (orçamento 31), e 128 em `renovacao_falhou` de `estacionado-trabalho` (orçamento 72). O trecho livre é neutralizado antes de entrar: quebras de linha e caracteres de controle viram espaço, sequência de espaços vira um, e ele vai entre aspas duplas depois de `log:`. O `motivo` de `manual_no_limite` NÃO é trecho livre (ver a linha dele abaixo).

Linhas por tipo (o texto é prescrito; `<...>` é dado). Data é `AAAA-MM-DD HH:MM` em UTC, do `em`. O nome da conta é `team`→`trabalho`, `pessoal`→`pessoal`:
- `vigia_falhou`: `- vigia: a rodada do vigia de troca de conta abortou em <data> UTC e a troca automática ficou sem decidir. Diagnóstico: node scripts/conta.cjs status (log: "<motivo>")`
- `pasta_sem_credencial`: `- pasta <pasta>: sem .credentials.json; o vigia a deixa fora da decisão e decide só pela outra pasta. Refaça o /login dela, ou renomeie a pasta se ela não é mais usada.`
- `renovacao_falhou` de `reserva-<conta>`: `- login guardado <nome>: a renovação falhou em <data> UTC; se o servidor recusa, refaça com: node scripts/conta.cjs preparar <nome da conta> --refazer (log: "<erro>")`; de `estacionado-<pasta>`: `- login guardado <nome>: a renovação falhou em <data> UTC; veja: node scripts/conta.cjs status (log: "<erro>")`
- `uso_ilegivel`: `- pasta <pasta>: o uso da conta <nome de "de"> está ilegível há mais de 30 min; sem ele a volta e o aviso de limite não disparam. Veja: node scripts/conta.cjs status`
- `manual_no_limite`: `- pasta <pasta>: na conta <nome de "de">, no limite (<limite legível> da conta <nome de "de"> em <n>%); sem volta automática (casa sem folga ou sem dado). Devolver: /conta <nome de "para"> --pasta <pasta>`; com `causa: sem_login_guardado`: `- pasta <pasta>: na conta <nome de "de">, no limite (<limite legível> da conta <nome de "de"> em <n>%); não há login guardado da conta <nome de "para">: faça /login dela na pasta <pasta>.` O `<limite legível>` e o `<n>` saem do `motivo` do evento (`<limite> de <conta> em <n>%`, que o `avisoManual` de `scripts/lib/conta-decidir.cjs` monta) pela mesma tradução do `motivoLegivel` de `hooks/conta-puro.mjs`, replicada na lib (a lib é CommonJS e não importa `.mjs`): `seven_day` vira `semana`, `five_hour` vira `janela de 5 h`, e `<n>` só vale se casar `^[\d.,]{1,6}%$`. Motivo que não casa `^(seven_day|five_hour) de (team|pessoal) em ([\d.,]{1,6}%)(?: \(>= [\d.,]+\))?$` sai sem o parêntese (`... no limite; sem volta automática ...`): nenhum texto livre desse campo chega à linha, por isso ele não passa pela neutralização. Exemplo literal (181 caracteres), para o evento `{"em":1,"tipo":"manual_no_limite","pasta":"trabalho","de":"pessoal","para":"team","motivo":"five_hour de pessoal em 100%","manual":true}`: `- pasta trabalho: na conta pessoal, no limite (janela de 5 h da conta pessoal em 100%); sem volta automática (casa sem folga ou sem dado). Devolver: /conta trabalho --pasta trabalho`.

Casos de `scripts/testa-conta-avisos.cjs` (30 ok, uma afirmação por caso listado ou subcaso numerado): (a1-1) `vigia_falhou` com `vigiaOkEm` mais novo fecha, (a1-2) com `vigiaOkEm` mais velho ou `null` abre; (a2-1) `pasta_sem_credencial` seguido de `pasta_com_credencial` fecha, (a2-2) sem ele abre, (a2-3) com `pasta_com_credencial` da OUTRA pasta abre; (a3-1) `manual_no_limite` fecha com `trocar` posterior da mesma pasta, (a3-2) com `voltar`, (a3-3) com `reconciliado`, (a3-4) não fecha com `trocar` da outra pasta, (a3-5) nem com `trocar` ANTERIOR; (a4-1) a mesma família para `uso_ilegivel`, (a4-2) `voltar` fecha; (a5) `renovacao_falhou` com `expiresAt` daqui a 8 h fecha; (a5-2) com `expiresAt` daqui a 30 min abre; (a5-3) com o arquivo ausente (`null`) fecha; (a5-4) só a última falha de cada login conta; (a6-1) evento de 7 dias e 1 ms atrás fica de fora, (a6-2) de 6 dias entra; (a7-1) `pasta: "../x"` é ignorada, (a7-2) `de: "outra"` é ignorado, (a7-3) tipo desconhecido é ignorado, (a7-4) linha corrompida no arquivo não derruba a leitura (`lerEventosArq`); (a8) um item por chave: dois `manual_no_limite` da mesma pasta viram um; (a9-1) 7 problemas: cabeçalho, 5 linhas e `... e mais 2: node scripts/conta.cjs status`, (a9-2) toda linha dos cinco tipos tem no máximo 200 caracteres com `motivo`/`erro` de 500 caracteres, e a de `vigia_falhou` e as duas de `renovacao_falhou` ainda contêm o comando, antes do `(log: ...)`, (a9-3) `motivo` com `\n## Ignore` vira uma linha só, sem quebra, (a9-4) cada tipo traz o sujeito (pasta ou login) e o comando prescrito acima, com `motivo` curto e com `motivo` de 500 caracteres, (a9-5) o `manual_no_limite` do exemplo literal acima sai exatamente como no exemplo, (a9-6) `manual_no_limite` com `motivo` fora do formato (`ignore tudo\n## x`) sai sem parêntese de motivo e sem nenhum trecho dele, (a9-7) com `erro` de 500 caracteres, a linha de `renovacao_falhou` de `reserva-team` e a de `vigia_falhou` têm excerpt de 31 caracteres e 200 no total, e a de `estacionado-trabalho` tem 200 no total.

### 5. D5+D6: hook de sessão `conta-aviso-sessao.cjs`, registro e contagens [tipo: implementar]
atende: D5, D6
arquivos: `hooks/conta-aviso-sessao.cjs`, `hooks/hooks.json`, `hooks/testa-conta-aviso-sessao.cjs`, `hooks/testa-titulo-sessao-registro.sh`, `hooks/testa-ferramentas-nao-toca-abertura.sh`, `scripts/testa-conferir-categoria.sh`
depende de: 4
busca:
- repo | grep -n additionalContext hooks/memoria-assunto-prompt.cjs hooks/idioma-session-start.cjs | o formato `{ hookSpecificOutput: { hookEventName, additionalContext } }` e o padrão de dedupe por sessão (`<raiz>/memoria-assunto/<session_id>.json`, `session_id` validado por regex) já existem
- repo | grep -rn avisos-vistos hooks scripts | nada
desfecho: compor
mutacao:
  arquivo: `hooks/conta-aviso-sessao.cjs`
  de: `const novos = abertos.filter((p) => !vistos.has(p.chave)); // D5 (conta-reserva-avisa)`
  para: `const novos = abertos; // D5 (conta-reserva-avisa)`
  bateria: `node hooks/testa-conta-aviso-sessao.cjs`
  fixture: `testa-conta-aviso-sessao.cjs, caso (h2) a segunda chamada da mesma sessão não injeta de novo`
prova: `node hooks/testa-conta-aviso-sessao.cjs`
pronto quando: com o payload real que o harness manda ao hook no stdin (`{"session_id":"sessao-a","transcript_path":"...","cwd":"...","hook_event_name":"SessionStart","source":"startup"}` e o de `UserPromptSubmit` com `"prompt":"oi"`), `RFM_CONTA_DADOS` apontando para um diretório temporário cujo `contas/eventos.jsonl` tem um problema aberto de cada tipo (`vigia_falhou`, `pasta_sem_credencial`, `renovacao_falhou` de `reserva-team` com `expiresAt` daqui a 10 min, `uso_ilegivel`, `manual_no_limite`), o hook sai 0 e imprime uma linha JSON com `hookSpecificOutput.hookEventName` igual ao evento recebido e `additionalContext` começando por `## Conta (regra 14)` seguido de uma linha por problema com a pasta ou o login e o comando; a segunda chamada com o mesmo `session_id` sai 0 sem imprimir nada; outro `session_id` recebe de novo; sem `eventos.jsonl`, ou com os problemas fechados, ou com eventos de mais de 7 dias, não imprime nada e não cria `avisos-vistos/`; `hooks.json` registra o hook uma vez em `SessionStart` (grupo novo, ao fim) e uma vez em `UserPromptSubmit` (ao fim do grupo existente), com `timeout` 5 — provado por `node hooks/testa-conta-aviso-sessao.cjs` terminando em `30 ok, 0 falha(s)` com exit 0, pela mutação acima deixando (h2) vermelho, e por `bash hooks/testa-titulo-sessao-registro.sh`, `bash hooks/testa-ferramentas-nao-toca-abertura.sh`, `bash scripts/testa-conferir-categoria.sh` e `node scripts/conferir-categoria.cjs` verdes com as contagens novas abaixo. Superfície humana: a pessoa (ou o modelo que a avisa) vê, por problema, a pasta ou o login e o comando que resolve; os casos (h1-1) a (h1-5) falham se o sujeito ou o comando sumir de uma linha.

Critério de trava (o hook não barra nada, mas lê um arquivo que qualquer processo do usuário escreve e injeta o resultado no contexto do modelo; por isso as duas faces):
- Contornos: `session_id` com `../` ou `/` ou vazio sai mudo e não grava nada fora de `avisos-vistos/`; `motivo` com quebra de linha e `## ` (injeção de seção) vira uma linha só, entre aspas, de até 80 caracteres; `pasta` fora de `trabalho`/`pessoal` e `de`/`para` fora de `team`/`pessoal` não entram; linha corrompida no `eventos.jsonl` é pulada; `avisos-vistos/<sessão>.json` corrompido conta como "nada visto"; stdin vazio, não JSON ou ausente sai 0 mudo.
- Casos legítimos vizinhos que NÃO podem ser barrados nem silenciados: o problema aberto de uma sessão nova aparece mesmo que outra sessão já o tenha visto; `UserPromptSubmit` e `SessionStart` da mesma sessão dividem o "já visto"; problema de 6 dias atrás ainda aparece; com `vigia.lock` preso por um processo vivo, o hook responde igual (não pega a trava).
- Parada: o hook não interpreta o texto livre do log, só o neutraliza e o corta. Evento forjado por quem já escreve em `<dados>/contas` fica fora do modelo de ameaça; se isso mudar, volta ao `brainstorm`.

Forma prescrita do hook (`#!/usr/bin/env node`, segunda linha `// @categoria: guia`, todo o corpo dentro de `try/catch` que sai 0): lê o JSON do stdin; exige `session_id` casando `/^[A-Za-z0-9_-]+$/` e `hook_event_name` igual a `SessionStart` ou `UserPromptSubmit`; resolve a pasta de dados por `dadosDir({ env: process.env, home: os.homedir(), plugin: path.resolve(__dirname, '..') })` da lib (nunca por `cwd` do payload: o `memoria-assunto-prompt.cjs` lê o `.rainforest` do projeto, aqui o certo é o do usuário, como o `conta.cjs`); lê `<dados>/contas/eventos.jsonl` por `lerEventosArq` (sem o arquivo, sai mudo sem criar nada); calcula `vigiaOkEm` (`mtimeMs` de `<dados>/contas/vigia-ok` ou `null`) e `expiraEm(nome)` (lê só `claudeAiOauth.expiresAt` de `<dados>/contas/<nome>.json`, `null` em qualquer erro) e chama `problemasAbertos`; lê `<dados>/contas/avisos-vistos/<session_id>.json` (array de chaves; ausente ou fora do formato = nenhuma) e apaga os arquivos dessa pasta com `mtime` de mais de 7 dias; filtra por uma expressão só, a linha da mutação (`abertos` é o que `problemasAbertos` devolveu e `vistos` um `Set` das chaves lidas); se `novos` estiver vazio sai mudo sem gravar; senão grava o arquivo da sessão com as chaves antigas mais TODAS as de `novos` (inclusive as que ficaram no "e mais N", senão a linha de excedente voltaria a cada turno), criando `avisos-vistos/` só aqui, e imprime `JSON.stringify({ hookSpecificOutput: { hookEventName, additionalContext: montarSecao(novos) } })`. Nenhum caso de teste pode afirmar sobre o texto do fonte.

Registro em `hooks/hooks.json`: em `SessionStart`, um grupo novo ao fim do array (depois do grupo `matcher: compact`), sem `matcher`, com `{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/conta-aviso-sessao.cjs\"", "timeout": 5 }`; em `UserPromptSubmit`, a mesma entrada ao fim do único grupo existente (depois do `memoria-assunto-prompt.cjs`).

Baterias de contagem que o registro toca (lista conferida por `grep -rln "hooks.json" hooks/testa-* scripts/testa-*` e leitura das asserções; as três primeiras mudam, as demais só rodam):
- `hooks/testa-titulo-sessao-registro.sh` (linha 87): `{"SessionStart":7,"PreToolUse":18,"Stop":6,"UserPromptSubmit":2}` vira `{"SessionStart":8,"PreToolUse":18,"Stop":6,"UserPromptSubmit":3}`, e o comentário de histórico ganha a linha de 2026-11-12 (conta-reserva-avisa, `hooks/conta-aviso-sessao.cjs`).
- `hooks/testa-ferramentas-nao-toca-abertura.sh` (linhas 53-72): `SessionStart` passa de 7 para 8 hooks (a asserção, a mensagem e o comentário), e ganha um caso logo depois do do `idioma-session-start`: o hook novo, com payload de `SessionStart` (`source: startup`) e `RFM_ROOT="$DADOS"` numa caixa sem `contas/eventos.jsonl`, sai 0 mudo (o próprio comentário do arquivo exige essa prova para subir a contagem).
  Texto literal do caso novo, colado logo depois do bloco do `idioma-session-start` (antes do `echo "== D4`):

```
EVENTO_CS="$(node -e 'process.stdout.write(JSON.stringify({hook_event_name:"SessionStart",session_id:"s-abertura",source:"startup",cwd:process.argv[1]}))' "$PROJ")"
SAIDA_CS="$(printf '%s' "$EVENTO_CS" | env -u RFM_CONTA_DADOS RFM_ROOT="$DADOS" node "$SRC/hooks/conta-aviso-sessao.cjs" 2>/dev/null)"; RC_CS=$?
if [ -z "$SAIDA_CS" ] && [ "$RC_CS" = "0" ]; then
  ok=$((ok+1)); echo "  ok   conta-aviso-sessao mudo na abertura (sem eventos.jsonl na caixa)"
else
  falhou=$((falhou+1)); echo "  FALHA conta-aviso-sessao na abertura: '$SAIDA_CS' (exit $RC_CS)"
fi
```

  E o comentário acima da contagem ganha: `# 8 desde 2026-11-12: entrou hooks/conta-aviso-sessao.cjs (conta-reserva-avisa). Sem eventos.jsonl ele sai mudo na abertura, provado logo abaixo.` Mensagens: `SessionStart continua com 8 hooks` e `SessionStart tem $QTD hooks, esperava 8`.
- `scripts/testa-conferir-categoria.sh` (linhas 95-105 e cabeçalho): 67 peças viram 68 e 25 guia viram 26 guia (o hook é `guia`: injeta contexto antes do ato, como `memoria-assunto-prompt.cjs`); o cabeçalho ganha a linha `68 e 26 guia desde 2026-11-12: entrou hooks/conta-aviso-sessao.cjs ...`. Conferir contra o que `node scripts/conferir-categoria.cjs` imprimir (`Total de peças varridas: 68`); o hook citado em duas entradas do `hooks.json` conta uma vez (base: 42 entradas para 37 arquivos distintos).
  Edições literais: no cabeçalho, depois da linha `#      67 e 39 sensor desde 2026-11-11: ...`, as duas linhas `#      68 e 26 guia desde 2026-11-12: entrou hooks/conta-aviso-sessao.cjs, hook` e `#      de SessionStart e UserPromptSubmit (injeta o problema de conta aberto antes do turno) — guia.`; `echo "== 1. repositorio real na base — exit 0, 67 pecas, distribuicao 25/39/3 =="` vira `... 68 pecas, distribuicao 26/39/3 ==`; `tem  "conta as 67 pecas" "$S1" "Total de peças varridas: 67"` vira `tem  "conta as 68 pecas" "$S1" "Total de peças varridas: 68"`; `[ "$N_GUIA" = "25" ]` vira `[ "$N_GUIA" = "26" ]`; as duas mensagens `distribuicao 25 guia / 39 sensor / 3 dado confere` e `(esperava 25/39/3)` viram 26.
- Só rodar, sem mudança esperada (o hook sai mudo sem `eventos.jsonl`): `bash scripts/testa-memoria-somente-leitura.sh` (mapeia a abertura por posição; o hook é o oitavo), `bash scripts/testa-orcamento.sh` (a seção 6e mede os hooks reais), `bash hooks/testa-memoria-recuperacao.sh`, `bash scripts/testa-exporta-hooks-sessao-start.sh`, `node hooks/testa-memoria-assunto-prompt.cjs`, `bash scripts/testa-observar.sh`, `bash scripts/testa-medir-injecao.sh`, `bash hooks/testa-contexto-sessao.sh`.

Casos de `hooks/testa-conta-aviso-sessao.cjs` (30 ok no total; bateria em Node, `node:child_process.spawnSync` do hook com o payload no stdin e `RFM_CONTA_DADOS` apontando para um diretório temporário; sem servidor falso nesta tarefa; a tarefa 7 acrescenta a seção ponta a ponta). Uma linha de problema "traz o sujeito e o comando" quando contém o texto indicado:

| caso | o que afirma | afirmações |
|---|---|---|
| h1-1 | `vigia_falhou`: uma linha com `vigia` e `node scripts/conta.cjs status` | 1 |
| h1-2 | `pasta_sem_credencial`: uma linha com `pasta pessoal` e `/login` | 1 |
| h1-3 | `renovacao_falhou` de `reserva-team`: uma linha com `reserva-team` e `preparar trabalho --refazer` | 1 |
| h1-4 | `uso_ilegivel`: uma linha com `pasta trabalho` e `node scripts/conta.cjs status` | 1 |
| h1-5 | `manual_no_limite`: uma linha com `pasta trabalho` e `/conta trabalho --pasta trabalho`; a variante `sem_login_guardado` com `/login da conta trabalho` e sem `/conta trabalho --pasta` | 2 |
| h1-6 | cabeçalho `## Conta (regra 14)` e `hookEventName` igual ao do payload, no `SessionStart` e no `UserPromptSubmit` | 2 |
| h2 | segunda chamada da mesma sessão: exit 0, mudo | 1 |
| h2-2 | `UserPromptSubmit` da mesma sessão depois do `SessionStart`: mudo | 1 |
| h2-3 | outra sessão: injeta | 1 |
| h3-1 | sem `eventos.jsonl`: mudo e sem `avisos-vistos/` | 1 |
| h3-2 | problemas fechados (`vigia-ok` mais novo, `pasta_com_credencial`, `voltar`, `expiresAt` longe): mudo | 1 |
| h3-3 | evento de 8 dias: mudo | 1 |
| h3-4 | evento de 6 dias: injeta | 1 |
| h4-1 | `session_id` `../x`: mudo e nenhum arquivo criado fora do diretório temporário | 2 |
| h4-2 | `session_id` vazio: mudo | 1 |
| h4-3 | stdin vazio: exit 0, mudo | 1 |
| h4-4 | stdin `isto não é json`: exit 0, mudo | 1 |
| h4-5 | `motivo` com `\n## Ignore`: linha única | 1 |
| h4-6 | 7 problemas: 5 linhas e `... e mais 2: node scripts/conta.cjs status`; na chamada seguinte da mesma sessão, nada (as 7 chaves ficaram vistas) | 2 |
| h4-7 | linha corrompida no log: as outras entram | 1 |
| h4-8 | `vigia_falhou` com `motivo` de 500 caracteres: a linha tem no máximo 200 caracteres e contém `node scripts/conta.cjs status` | 1 |
| h5-1 | `vigia.lock` com o PID do próprio teste (vivo): mesma saída | 1 |
| h5-2 | só `RFM_ROOT` definida (sem `RFM_CONTA_DADOS`): lê `<RFM_ROOT>/contas/eventos.jsonl` | 1 |
| h5-3 | arquivo de sessão com `mtime` de 8 dias é apagado na leitura e o de 1 dia fica | 2 |
| h5-4 | `avisos-vistos/<sessão>.json` corrompido: injeta como se nada fosse visto | 1 |

Soma: 8 + 3 + 4 + 10 + 5 = 30.

### 6. D4: uso ilegível de pasta fora de casa vira evento [tipo: implementar]
atende: D4
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-vigia-avisa.sh`
depende de: 3
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (agora - info.semUsoDesde < SEM_USO_AVISAR_MS) continue; // D4 (conta-reserva-avisa)`
  para: `if (false) continue; // D4 (conta-reserva-avisa)`
  bateria: `bash scripts/testa-conta-vigia-avisa.sh`
  fixture: `testa-conta-vigia-avisa.sh, casos (d4-1) e (d4-2)`
prova: `bash scripts/testa-conta-vigia-avisa.sh`
pronto quando: com um home temporário no formato real montado assim (fixture de `scripts/testa-conta.sh`, `novo_caso d4 sim`): `ajustar.cjs trocado` (põe a pasta `trabalho` na conta pessoal; deixa `manual: false` e um `travouPor` já passado, e vence só `estacionado-trabalho` e `reserva-team`, não o login da pasta); depois, no `estado.json`, `pastas.trabalho.manual = true` e `travouPor = null` (o mesmo `node -e` do bloco `#584`; sem isso a volta automática comum devolveria a pasta e o cenário acabaria); e `claudeAiOauth.expiresAt = 1` no `trabalho/.claude/.credentials.json` (é o login da conta pessoal que a pasta carrega: com ele vencido e `reserva-pessoal.json` vazia, como o `ajustar` a deixa, o uso da conta pessoal fica ilegível, "login vencido"), a primeira rodada de `node scripts/conta.cjs vigiar` grava `pastas.trabalho.semUsoDesde` (número, epoch ms) no `estado.json` e nenhum evento; com `semUsoDesde` 29 min atrás não grava `uso_ilegivel`; com 31 min atrás grava exatamente um `{"tipo":"uso_ilegivel","pasta":"trabalho"...}` e a rodada seguinte não grava outro; quando o dado de uso volta (o `claudeAiOauth.expiresAt` do mesmo arquivo restaurado para `4102444800000`, o servidor falso devolve o uso da pessoal, abaixo do `trocarEm`), a rodada seguinte remove `semUsoDesde`; vencido de novo e com `semUsoDesde` 31 min atrás, grava o segundo evento; num caso à parte com as duas pastas em casa (`novo_caso` sem `ajustar`, `expiresAt = 1` no `trabalho/.claude/.credentials.json` E em `reserva-team.json`, senão a reserva ainda lê o uso da team), a rodada não grava `semUsoDesde` nem evento — provado por `bash scripts/testa-conta-vigia-avisa.sh` terminando em `ok: 36   falhou: 0` com exit 0, e pela mutação acima deixando (d4-1) e (d4-2) vermelhos (sem a espera, a mesma rodada que grava `semUsoDesde` já gravaria o evento).

Forma prescrita: em `vigiar` (a função `vigiarRodada` da tarefa 3), logo depois de `const usos = await coletarUsos(c, estado);`, chamar `avisarUsoIlegivel(c, estado, pastas, usos);`, definida acima de `vigiar` junto de `const SEM_USO_AVISAR_MS = 30 * 60 * 1000;`. Para cada `P` de `Object.keys(pastas)` (só as pastas que entraram na decisão), com `info = estado.pastas[P]`, `agora = Date.now()` e `legivel` = `usos[info.conta]` com `five_hour` e `seven_day`: pasta em casa (`info.conta === info.casa`) ou dado legível apaga `info.semUsoDesde` (se existia) e dá `continue`; falta de dado sem `semUsoDesde` grava `info.semUsoDesde = agora` e SEGUE para a linha da mutação (sem `continue` próprio): lá `agora - info.semUsoDesde` é 0, menor que `SEM_USO_AVISAR_MS`, e a linha dá `continue`; passados os 30 min, grava `{ tipo: 'uso_ilegivel', pasta: P, de: info.conta, para: info.casa, motivo: 'sem dado de uso de <nome da conta> há <n> min', manual: info.manual }` por `registrarEvento`, salvo se `lerEventos(c)` já tiver um `uso_ilegivel` dessa pasta com `em >= info.semUsoDesde` (uma vez por período). Qualquer mudança no `semUsoDesde` termina em `gravarEstado(c, estado)` (o `lerEstado` preserva campos extras: `...gravado`). Nenhum caso de teste pode afirmar sobre o texto do fonte.

Casos (home temporário como na tarefa 1): (d4-1) primeira rodada: `semUsoDesde` numérico e zero `uso_ilegivel` (2 afirmações); (d4-2) `semUsoDesde` = agora − 29 min: zero eventos (1); (d4-3) agora − 31 min: um evento, e depois de segunda rodada ainda um (2); (d4-4) dado volta: `semUsoDesde` ausente no `estado.json` (1); (d4-5) novo período (`semUsoDesde` = agora − 31 min de novo): total de dois eventos (1); (d4-6) pasta em casa com uso ilegível: sem `semUsoDesde`, sem evento (2).

### 7. D5: o `conta.cjs` e o hook falam do mesmo critério, e o hook lê os eventos que o vigia grava de verdade [tipo: implementar]
atende: D5
arquivos: `scripts/conta.cjs`, `hooks/testa-conta-aviso-sessao.cjs`
depende de: 5, 6
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `const abertas = AVISOS.falhasDeRenovacao(eventos, expiraEm, Date.now()); // D5 (conta-reserva-avisa)`
  para: `const abertas = AVISOS.falhasDeRenovacao(eventos, () => 0, Date.now()); // D5 (conta-reserva-avisa)`
  bateria: `node hooks/testa-conta-aviso-sessao.cjs`
  fixture: `testa-conta-aviso-sessao.cjs, caso (e2e-3)`
prova: `node hooks/testa-conta-aviso-sessao.cjs`
pronto quando: com um home temporário no formato real e o servidor falso, depois de rodadas REAIS de `node scripts/conta.cjs vigiar`, o hook com o payload real de `SessionStart` injeta: a linha de `pasta_sem_credencial` quando a pasta pessoal não tem `.credentials.json` (e some, em outra sessão, depois de a credencial voltar e uma rodada gravar `pasta_com_credencial`); a linha de `vigia_falhou` quando o `estado.json` está corrompido (e some, em outra sessão, depois de uma rodada completa); a linha de `renovacao_falhou` de `reserva-team` quando o servidor responde 500 à renovação com a reserva vencendo em menos de 1 h, e essa mesma falha aparece no `status` (`aviso: a renovação de reserva-team falhou`) e some dos DOIS quando o login é renovado (`expiresAt` longe); a linha de `uso_ilegivel` com `semUsoDesde` 31 min atrás; e `scripts/conta.cjs` e o hook acham o mesmo `eventos.jsonl` só com `RFM_ROOT` definida (sem `RFM_CONTA_DADOS`) — provado por `node hooks/testa-conta-aviso-sessao.cjs` terminando em `39 ok, 0 falha(s)` com exit 0, pela mutação acima deixando (e2e-3) vermelho (o login já renovado continuaria aparecendo no `status`), e por `bash scripts/testa-conta.sh`, `bash scripts/testa-conta-vigia-avisa.sh` e `node scripts/conferir-caixas.cjs` (sem passar de 128 achados) verdes.

Forma prescrita em `scripts/conta.cjs`: `const AVISOS = require('./lib/conta-avisos.cjs');` junto dos outros `require`; apagar a linha `const RENOVAR_ANTES_MS = 60 * 60 * 1000;` e trocá-la por `const { RENOVAR_ANTES_MS } = AVISOS;` (um só valor, na lib); `dadosDir()` passa a chamar `AVISOS.dadosDir({ env: process.env, home: os.homedir(), plugin: path.resolve(__dirname, '..') })` e a lançar `new Error('sem pasta de dados do rainforest (defina RFM_CONTA_DADOS)')` se vier `null` (mesma mensagem de hoje); `falhasDeRenovacao(c)` passa a montar `eventos = lerEventos(c).map(({ ev }) => ev)`, um `expiraEm(nome)` que lê `claudeAiOauth.expiresAt` de `<contas>/<nome>.json` (por `lerJson`, `null` em qualquer erro), a linha da mutação, e a MESMA formatação de linha de hoje (`aviso: a renovação de <nome> falhou em <ISO> (<erro>)` mais o `; se o servidor recusa, refaça: preparar <conta> --refazer` das reservas). A saída de `status` não muda nada em relação à base. Nenhum caso de teste pode afirmar sobre o texto do fonte.

A bateria já tem, na linha 3, o marcador `rainforest-gate: dados-de-exemplo` (posto na integração: o `gate-publicacao-destino.cjs` barrava a edição pelos tokens falsos, como faz com `hooks/testa-mod-conta.cjs`). Seção ponta a ponta acrescentada a `hooks/testa-conta-aviso-sessao.cjs` (a tarefa 5 criou a bateria): sobe o `scripts/fixtures/conta/servidor.cjs` como o `hooks/testa-mod-conta.cjs` faz (porta livre, morto no `finally`), monta o home com a fixture do `semear` (mesma lista de variáveis `RFM_*` da tarefa 1) e roda o `conta.cjs` e o hook de verdade. Casos: (e2e-1) `pasta_sem_credencial` real, depois `pasta_com_credencial` real (2 afirmações); (e2e-2) `vigia_falhou` real, depois `vigia-ok` (2); (e2e-3) `renovacao_falhou` real, no `status` e no hook, e o fechamento nos dois (3); (e2e-4) `uso_ilegivel` com `semUsoDesde` forjado no `estado.json` (1); (e2e-5) só `RFM_ROOT`: os dois acham o mesmo log (1). 30 + 9 = 39 `ok`.

### 8. D3: a linha de status da pasta manual diz que ela volta [tipo: implementar]
atende: D3
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-vigia-avisa.sh`
depende de: 7
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (info.manual) linha += ' · troca manual (volta se a conta em uso chegar ao limite e a de casa tiver folga)';`
  para: `if (info.manual) linha += ' · troca manual (sem volta automática)';`
  bateria: `bash scripts/testa-conta-vigia-avisa.sh`
  fixture: `testa-conta-vigia-avisa.sh, caso (st-1)`
prova: `bash scripts/testa-conta-vigia-avisa.sh`
pronto quando: com um home temporário no formato real, a pasta `trabalho` na conta pessoal com `manual: true` e o servidor falso, `node scripts/conta.cjs status` imprime, na linha de `pasta trabalho`, `troca manual (volta se a conta em uso chegar ao limite e a de casa tiver folga)` e não imprime `sem volta automática` em lugar nenhum — provado por `bash scripts/testa-conta-vigia-avisa.sh` terminando em `ok: 37   falhou: 0` com exit 0 (35 + (st-1) com 2 afirmações), e pela mutação acima deixando (st-1) vermelho. Superfície humana: quem lê o `status` vê a condição da volta (conta em uso no limite e casa com folga), que é a informação de que precisa para saber se deve esperar ou trocar na mão; a frase não cita número de limite, que vem do `config.json`.

### 9. Versão 2.13.0, README, CHANGELOG e `commands/conta.md` [tipo: docs]
atende: D1, D2, D3, D4, D5, D6
arquivos: `README.md`, `commands/conta.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2, 5, 8, 10
mutacao: n/a
  motivo: só texto e número de versão; o comportamento está medido pelas tarefas 1 a 8, e a falsificação é a coerência do texto com o design e com o código
pronto quando: `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (os dois `plugin.json`, o selo do README com `vers%C3%A3o-2.13.0-` e `alt="versão 2.13.0"`, o topo do CHANGELOG `## 2.13.0 — 2026-11-12`) dizem 2.13.0 (MINOR: hook novo e contrato novo da troca manual; se o PR do `gate-segmentador` entrar antes, 2.13.0 continua maior que 2.12.3); `README.md:311` e `:338` e `commands/conta.md:19` deixam de dizer que a troca manual nunca volta sozinha e dizem a regra da D3 (volta quando a conta em uso chega ao `trocarEm` na 5 h ou na semana e a conta de casa tem folga, com login estacionado; sem isso, só o aviso `manual_no_limite`); a seção "Troca automática de conta" do README nomeia os eventos novos (`pasta_sem_credencial`, `pasta_com_credencial`, `vigia_falhou`, `uso_ilegivel`) com o que cada um quer dizer, diz que o vigia não aborta mais por pasta sem credencial (D1), que a rodada que aborta é gravada uma vez por motivo (D2), os 30 min do `uso_ilegivel` (D4) e descreve o hook `conta-aviso-sessao.cjs` (`SessionStart` e `UserPromptSubmit`; lê só o `eventos.jsonl`, uma vez por sessão e problema, até 7 dias, no máximo 5 linhas de 200 caracteres mais a linha de excedente) ao lado do `idioma-session-start.cjs` em `README.md:214`; a entrada do CHANGELOG diz, pelo comportamento, o que o usuário passa a ver (Issue 693: o vigia que travava em silêncio com `~/.claude-personal` sem credencial, a pasta trocada à mão que volta, o aviso na sessão) e nomeia o limite aceito (recorrência do mesmo problema não é re-anunciada na mesma sessão) — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m1 -A6 '^## ' CHANGELOG.md; grep -n 'não volta sozinha\|sem volta automática' README.md commands/conta.md` (o último `grep` sem saída), e por leitura cruzada na revisão: os números 30 min, 7 dias, 5 linhas e 200 caracteres do texto são os do design.

### 10. D3: as duas frases do toast deixam de dizer que a pasta manual não volta [tipo: implementar]
atende: D3
arquivos: `hooks/conta-puro.mjs`, `hooks/testa-mod-conta.cjs`
depende de: nenhuma
mutacao:
  arquivo: `hooks/conta-puro.mjs`
  de: `' (troca manual; volta sozinha se a conta chegar ao limite e a de casa tiver folga).'`
  para: `' (troca manual; não volta sozinha).'`
  bateria: `node hooks/testa-mod-conta.cjs`
  fixture: `testa-mod-conta.cjs, a asserção da linha 169 "troca manual vira aviso com a pasta, a conta e a marca de manual"`
prova: `node --input-type=module -e 'import("./hooks/conta-puro.mjs").then((m)=>{const f=m.frase({tipo:"trocar",pasta:"trabalho",de:"team",para:"pessoal",manual:true,motivo:"manual"});process.exit(/não volta sozinha/.test(f)?1:0)})'`
pronto quando: com o evento que `/conta pessoal --pasta trabalho` grava (`{"em":1,"tipo":"trocar","pasta":"trabalho","de":"team","para":"pessoal","motivo":"manual","manual":true}`), `frase()` devolve `Conta: a pasta trabalho passou da conta trabalho para a conta pessoal (troca manual; volta sozinha se a conta chegar ao limite e a de casa tiver folga).`; com o `manual_no_limite` de `hooks/testa-mod-conta.cjs:240` (e a variante `sem_login_guardado` da linha 243), a frase diz `A troca foi manual e a volta automática não aconteceu: ` antes do comando (`/conta trabalho --pasta trabalho`) ou do `/login`, e nenhuma das duas frases contém `não volta sozinha` — provado por `node hooks/testa-mod-conta.cjs` terminando em `33 ok, 0 falha(s)` (32 da base mais o caso novo (m67); a asserção da linha 169 muda de texto, não de contagem) e pela mutação acima deixando a asserção da linha 169 vermelha. Superfície humana: quem lê o toast deixa de ser informado de que a pasta "não volta sozinha" quando ela volta; as asserções existentes das linhas 241 a 245 (pasta, conta, percentual e comando que devolve, com `--pasta`; `/login` quando não há login guardado) seguem verdes, para o aviso continuar dizendo o que fazer.

Forma prescrita em `hooks/conta-puro.mjs`: na linha 41, o final `' (troca manual; não volta sozinha).'` vira `' (troca manual; volta sozinha se a conta chegar ao limite e a de casa tiver folga).'`; na linha 67, `'). A troca foi manual e não volta sozinha: '` vira `'). A troca foi manual e a volta automática não aconteceu: '`; o comentário da linha 63 (`a pasta trocada na mão não volta sozinha (D8)`) passa a dizer que a volta é a da D3 de conta-reserva-avisa. Em `hooks/testa-mod-conta.cjs`: a expectativa da linha 169 troca o texto pelo novo, e o caso novo (m67), um único `afirma` (as duas frases juntas por `&&`), afirma, para o `manual_no_limite` das linhas 240 e 243, que a frase contém `a volta automática não aconteceu` e não contém `não volta sozinha`. Nenhum caso de teste pode afirmar sobre o texto do fonte, só sobre o que `frase()` devolve.

## Premissas aceitas sem conferir

Quem despachou é o único que pode corrigir estas; o resto do plano saiu de arquivo lido ou comando rodado na base `71912254`.

- Que `.claude-personal` existindo sem credencial, com a pasta `trabalho` manual, reproduz a tabela de medição do design (o design a mediu; só li o código dos três ramos e não refiz a medição com o servidor falso).
- Que o `eventos.jsonl` é gravado só por `registrarEvento` e lido só por `lerEventos` e pelo `conta.cjs eventos` (o mod): não procurei outro escritor fora de `scripts/conta.cjs`.
- Que a regra "arquivo novo na pasta de dados nasce com três portas" (CONTRIBUTING) não se aplica a `vigia-ok` e a `avisos-vistos/`: `scripts/setup.cjs` não lista nenhum arquivo de `<dados>/contas/` na `ARQUIVOS` (o `grep` por `eventos.jsonl`, `estacionado` e `vigia.lock` voltou vazio), então não há precedente; não li o `/saude` para ver se vigia algo de `contas/`.
- Que o hook novo não precisa de chave de config (fica ligado): o CONTRIBUTING pede padrão falso só para dependência externa, e este hook lê um arquivo local sem rede nem serviço.
- Que o harness entrega `session_id` e `hook_event_name` no stdin de `SessionStart` e de `UserPromptSubmit` (visto no `hooks/testa-memoria-assunto-prompt.cjs` e no `hooks/idioma-session-start.cjs`, não na documentação do Claude Code desta versão).
- Que `SessionStart` com `source` `compact` ou `resume` pode reinjetar: o "já visto" é por `session_id`, que o harness mantém no `resume`; não conferi.
- Que o hook novo sai mudo nas baterias que rodam a abertura real (`testa-memoria-somente-leitura.sh`, `testa-orcamento.sh`, `testa-medir-injecao.sh`, `testa-contexto-sessao.sh`): sem `session_id` no stdin ele não imprime; só li as duas primeiras por cima e a tarefa 5 manda rodá-las.
- Que `scripts/testa-conta-vigia-avisa.sh` e `hooks/testa-conta-aviso-sessao.cjs` rodam em bem menos de 5 min cada (não medi; as três baterias vizinhas medidas: `testa-conta-decidir.cjs` 0 s, `testa-mod-conta.cjs` 2 s, `testa-conta.sh` 89 s); se passarem de 5 min, as tarefas 1, 3, 6, 7 e 8 precisam de `timeout:` no bloco `mutacao:`.
- Que a pasta com `expiresAt` vencido continua passando por `reconciliar` e `registrarCasas` com o servidor falso (o servidor falso não olha o `expiresAt` local): só li o código; a tarefa 6 mede.
- As contagens de `ok` (14, 27, 30, 30, 30+9=39, 36, 38, 40, 74 e, na tarefa 10, 33) são as dos casos listados em cada tarefa, somadas à mão; se o executor somar de outro jeito, corrige o número no plano antes de fechar.
- Que a posição 8 do hook novo (grupo novo ao fim de `SessionStart`) não quebra a leitura do `testa-memoria-recuperacao.sh` (`grep -A 20 '"SessionStart"'`): o grupo novo vem depois da janela de 20 linhas; só li a asserção.
