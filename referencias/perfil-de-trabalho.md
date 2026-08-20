# Perfil de trabalho do usuário

Este arquivo é a **fonte** do bloco que entra no system prompt dos sete
`agents/*.md`. Não edite os agentes à mão: edite aqui e rode
`node scripts/perfil.cjs --aplicar`. A bateria `scripts/testa-perfil.sh`
reprova se algum agente divergir da fonte — mesmo princípio do
`testa-versao.sh`, e pela mesma razão: **valor que existe em sete lugares
diverge em silêncio.**

## Por que existe

As 17 regras da skill descrevem como o assistente deve se comportar. Elas são
injetadas na janela principal e **não chegam ao subagente** — o agente recebe o
que estiver no `agents/*.md` dele e o que a janela principal escrever no
briefing. Na prática, isso significa que o padrão de evidência do usuário era
recontado à mão, em prosa, a cada despacho, e o que era esquecido não existia.

Cada linha do bloco abaixo saiu de **erro registrado**, não de suposição sobre
como ele gostaria de trabalhar. A procedência está aqui; o bloco injetado não a
carrega, para não gastar bytes no system prompt.

## Procedência de cada linha

| linha do bloco | de onde saiu |
|---|---|
| Config mudada não conta até reiniciar | `config-mudada-sem-reiniciar-processo` — mudança declarada pronta com o processo lendo o valor velho |
| Medidor improvisado mente | `medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia` — duas medições erradas na mesma sessão, e nas duas a fonte do erro foi o medidor, não o medido |
| Controle que compartilha o confundidor | `controle-que-compartilha-o-confundidor-nao-e-controle` — suíte rodada numa branch antiga para isolar causa, com as duas execuções lendo o mesmo arquivo vivo |
| Parâmetro calibrado em amostra | `limiar-calibrado-em-fatia-nao-vale-na-gravacao-inteira` — limiar calibrado em 5 min aplicado a 3h14: 5 falantes na fatia, 61 no todo |
| Mutação mantém o artefato funcionando | `falsificacao-exigida-passa-por-vacuidade` e `obs-2026-08-17-dez-baterias-que-nao-sabiam-falhar` — dez de dezoito entregas de agente com teste incapaz de falhar |
| Branch alheia não recebe trabalho novo | `commitar-em-branch-alheia-atrapalha-outra-sessao` |

## O que deliberadamente NÃO está no bloco

- **O que já está nos sete agentes.** A cláusula de premissa (de
  `premissa-afirmada-sem-ser-olhada`) já entrou em todos em 2026-08-13;
  repetir custaria bytes sem mudar comportamento.
- **O que é da conversa, não do trabalho.** Como ele quer ser respondido —
  prosa curta com uma pergunta aberta quando pede para conversar, confirmação
  de emenda no topo e não enterrada, "envia direto" tratado como ordem — vale
  para a **janela principal**, que já recebe as 17 regras. Agente não conversa
  com ele.
- **Traço inferido de comportamento.** Nada aqui foi deduzido de transcrito.
  Tudo saiu de correção que ele fez e que virou observação registrada. Perfil
  inferido erra em silêncio e enviesa todo despacho; perfil afirmado por ele
  pode ser derrubado por ele.

## O bloco

Tudo entre os marcadores é o que vai para os agentes, literalmente.

<!-- perfil-de-trabalho:inicio -->
## O padrão de evidência de quem recebe este trabalho

As linhas abaixo saíram de erro real e registrado. Elas valem para você como
valem para a janela principal.

- **Config mudada não conta até o processo que a lê ser reiniciado e a saída
  real mostrar o valor novo.** Arquivo salvo é intenção, não entrega.
- **Medidor improvisado mente, e mente confiante.** Meça na língua do medido:
  payload emitido por node se mede em node. Atravessar fronteira de ferramenta
  só para medir já é o defeito.
- **Controle que compartilha o confundidor não é controle.** Antes de usar
  "rodei na versão anterior e deu igual" como prova de que algo não é a causa,
  responda por escrito: o que esse controle lê que a execução suspeita também lê?
- **Parâmetro calibrado em amostra vale só para a amostra.** Antes de aplicar
  ao todo, rode no todo — ou confira numa segunda amostra independente.
- **Mutação tem que manter o artefato funcionando.** Teste que passa com o
  defeito presente não é teste. A mutação que prova isso **reverte o
  comportamento** mantendo mesma aridade e mesmo contrato; mutação que quebra a
  execução mede o `catch`, não o comportamento.
- **Branch que já é de outra sessão não recebe trabalho novo.** Antes do
  primeiro commit, cheque de quem é: esteira em aberto ou modificação alheia no
  working tree significa criar branch própria.
<!-- perfil-de-trabalho:fim -->
