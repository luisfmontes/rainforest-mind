---
name: depurar
description: Use quando algo está quebrado, falhando, com erro, lento ou intermitente — bug difícil, regressão de performance, comportamento que não reproduz, "funciona aqui e não lá". Constrói o loop de feedback antes de levantar hipótese.
---

# Depurar

Protocolo para bug difícil. Bug trivial — stack trace apontando a linha, erro
de digitação, campo com nome errado — não precisa disto: conserta e segue.

## Fase 1 — o loop de feedback vem antes da hipótese

**Esta fase é a skill.** Com um sinal apertado que fica **vermelho neste
bug**, o resto é mecânico: bisseção, teste de hipótese e instrumentação só
consomem o loop. Sem ele, olhar código não resolve nada — produz teoria
bonita e correção no lugar errado.

O portão: **se você se pegar lendo código para montar teoria antes de esse
comando existir, pare.** Pular direto para a hipótese é exatamente a falha
que este protocolo previne.

### Formas de construir, mais ou menos nesta ordem

1. Teste que falha, na costura que alcança o bug.
2. Invocação de CLI/função com entrada fixa, comparando a saída com uma boa
   conhecida.
3. Chamada HTTP contra ambiente rodando.
4. Replay de artefato capturado — salvar o payload, registro ou log real e
   reprocessá-lo isolado.
5. Harness descartável: o mínimo do sistema que exercita o caminho do bug
   numa chamada só.
6. Loop diferencial: mesma entrada na versão velha e na nova, diff das saídas.
7. Bisseção automatizada, quando o bug apareceu entre dois estados conhecidos.
8. Script de browser headless (Playwright), quando o sintoma é de tela.
9. Loop de propriedade/fuzz, quando o sintoma é "às vezes sai errado": mil
   entradas aleatórias procurando o modo de falha.

Em ERP legado a costura barata quase sempre é a (2) ou a (4): função
chamada por um fonte de teste com registro fixo e saída comparada, ou o
registro real do cliente copiado para o ambiente e reprocessado.

### Apertar o loop

Trate o loop como produto. Tendo *um* loop, aperte: **mais rápido** (cortar
init que não interessa, estreitar o escopo), **sinal mais afiado** (afirmar o
sintoma exato, não "não estourou"), **mais determinístico** (fixar data,
semente, isolar arquivo, congelar rede). Loop instável de 30 segundos mal
supera não ter loop; loop determinístico de 2 segundos é superpoder.

### Bug intermitente

A meta não é repro limpo, é **taxa de reprodução maior**. Repetir o gatilho
100×, paralelizar, estressar, estreitar a janela de tempo, injetar espera.
50% é depurável; 1% não é — subir a taxa até ficar.

### Critério de conclusão

A fase 1 fecha quando você consegue nomear **um comando**, já rodado ao menos
uma vez (mostrando a invocação e a saída), que é:

- **Vermelho-capaz** — percorre o caminho real e afirma o **sintoma exato que
  o Luís descreveu**, então fica vermelho neste bug e verde quando corrigido.
  "Roda sem erro" não serve.
- **Determinístico** — mesmo veredito toda vez (intermitente: taxa alta e
  fixada).
- **Rápido** — segundos.
- **Rodável sozinho** — sem gente na frente para clicar.

Não conseguiu construir? **Diga isso explicitamente**, liste o que tentou e
peça uma das três: acesso ao ambiente que reproduz, artefato capturado (log,
dump, registro), ou permissão para instrumentar. Seguir sem loop é chute com
aparência de método.

## Fase 2 — reproduzir e minimizar

Rodar e ver ficar vermelho. Confirmar que é **o sintoma que o Luís
descreveu** — falha vizinha leva a correção errada — e que repete.

Depois encolher até o menor cenário que ainda fica vermelho: cortar entrada,
chamador, configuração, dado e passo **um por vez**, rodando de novo a cada
corte. Pronto quando cada elemento restante for essencial: tirar qualquer um
deixa verde. Repro mínimo encolhe o espaço de hipóteses e vira o teste de
regressão da fase 5.

## Fase 3 — hipóteses ranqueadas antes de testar

Gerar **3 a 5 hipóteses ranqueadas antes de testar qualquer uma** — hipótese
única ancora na primeira ideia plausível e o resto da sessão vira confirmação
dela. Cada uma precisa ser falseável, com a previsão enunciada: "se X é a
causa, mudar Y faz o bug sumir". Sem previsão enunciável é palpite: descarta
ou afia.

**Saída ruim de modelo: a entrega vem antes da capacidade.** Quando o
sintoma é "o prompt automatizado devolveu coisa incompleta ou estranha", a
hipótese nº 1 é a **entrega** — o texto chegou inteiro? no encoding certo? —
e nunca "o modelo é fraco". Provar primeiro: tamanho do que foi enviado
contra o que chegou, última linha recebida, acentuação. Só depois de o
conteúdo íntegro estar provado é que o modelo entra em suspeita. Em
2026-08-08 o jardineiro perdeu 3 de 5 rondas e subir de haiku para sonnet não
mudou nada: o prompt chegava com metade dos caracteres e em mojibake. Subir
modelo é a correção mais cara e a mais fácil de confundir com solução.

Mostrar a lista ranqueada ao Luís antes de instrumentar — ele reordena na
hora com o que sabe do cliente e do histórico ("mexemos nisso semana
passada"). Checkpoint barato. Não travar esperando: se ele estiver fora,
seguir pela sua ordem.

## Fase 4 — instrumentar

Cada sonda mapeia uma previsão da fase 3. **Uma variável por vez.**

Preferir inspeção em debugger/REPL — um breakpoint vale dez logs. Depois, log
direcionado à fronteira que separa duas hipóteses. Nunca "loga tudo e greppa".

**Todo log de depuração leva prefixo único** — `[DEBUG-a4f2]`, incluindo em
linguagem de ERP legado (`conout("[DEBUG-a4f2] ...")`). A limpeza da fase 6 vira um grep só:
log marcado morre, log sem marca sobrevive por engano.

Regressão de performance tem ramo próprio: log costuma enganar. Estabelecer
baseline medido (timer, profiler, plano de execução da query) e então
bisseccionar. Medir primeiro, corrigir depois.

## Fase 5 — corrigir, com teste na costura certa

Teste de regressão **antes** da correção — e só se existir costura correta:
aquela que exercita o padrão real do bug como ele acontece no chamador.
Costura rasa demais (teste unitário que não consegue montar a cadeia que
disparou o bug) dá falsa confiança, que é pior que teste nenhum.

**Não existir costura correta é o achado.** Registrar: é a arquitetura
impedindo o bug de ser travado, e isso vale mais que o conserto pontual.

Havendo costura: virar o repro mínimo em teste que falha → ver falhar →
aplicar a correção → ver passar → rodar de novo o loop da fase 1 contra o
cenário **original**, não o minimizado.

## Fase 6 — limpar e fechar

- Repro original não reproduz mais (rodando o loop, não por dedução).
- Teste de regressão passa, ou a ausência de costura está registrada.
- Todo `[DEBUG-...]` removido — grep do prefixo para conferir.
- Protótipo e harness descartáveis apagados.
- **A hipótese que se confirmou entra na mensagem do commit** — quem depurar
  o próximo bug dessa área aprende com ela.

Fecha perguntando: **o que teria evitado este bug?** Resposta estrutural
(costura ausente, chamadores emaranhados, acoplamento escondido) é observação
da regra 13 — registra e segue, não vira refactor agora.

---

Destilado de `diagnosing-bugs` (mattpocock/skills, MIT), filtrado para a
stack do Luís e ancorado na regra 12: entrega se valida na saída real.
