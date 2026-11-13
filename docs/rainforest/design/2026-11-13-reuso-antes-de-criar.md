# Reuso antes de criar: catálogo lê Method TLPP, plano consulta o catálogo, revisar barra a cópia

## Objetivo
Impedir que o fluxo crie função que já existe no repositório. O plano consulta o catálogo de
funções antes de cada tarefa de código, e o revisar barra a duplicata que escapou. Hoje a
duplicata só aparece depois, se alguém rodar o `enxugar` modo 2.

A evidência vem do `enxugar` modo 2 no template Gestão de Projetos de um repositório Protheus de
trabalho, rodado em 2026-11-13. Saíram 15 `duplicar:` e 24 a investigar. Comentários como "mesma
regra de reembolso.view.tlpp" e "molde de RetratoAcesso" mostram que a cópia foi consciente: quem
gerou sabia que a função existia e copiou. O `busca:` do plano não pegaria nenhum desses casos,
porque só cobra tarefa que cria **arquivo** novo, e as cópias nasceram em arquivos que já
existiam. O catálogo também não enxergava os 142 `Method ... Class` daquele template, e era ali
que estava a subconsulta SQL repetida 11 vezes.

Decidido com o Luís na conversa de 13/11 e na rodada do brainstorm, com as cinco perguntas
aceitas como recomendadas e o resto em modo automático.

## Decisões fechadas
- **D1 — Público e momento: quem roda o fluxo do rainforest, em toda linguagem que o catálogo lê, no `plano` para prevenir e no `revisar` como rede de segurança** — porquê: o plano é onde a cópia ainda não nasceu; o revisar pega o que o plano não previu. As squads Protheus que não usam o rainforest ficam com uma réplica sem dependência no plugin protheus, em trabalho próprio do Luís, fora deste repositório.
- **D2 — O `busca:` ganha o canal `catalogo`, obrigatório em toda tarefa `implementar` (ou sem tipo) que declara código em `arquivos:`, e não só na que cria arquivo** — porquê: reaproveita o sensor (`conferir-busca.cjs`) e o formato que já existem, e fecha o buraco de "o arquivo já existia". Forma: `- catalogo | listar --raiz <pasta> | <resultado>`. O resultado diz `reaproveito <nome> de <arquivo>:<linha>` ou `nada equivalente`. `- catalogo | pulado: <motivo>` vale para tarefa que não cria função, como correção dentro de uma função. O critério de "código" é o mesmo de hoje: teste, `.md` e glob não contam.
- **D3 — O `conferir-busca` confere cada `<arquivo>:<linha>` citado na linha `catalogo` contra as definições daquele arquivo, lidas pelo catálogo** — porquê: a regra 12 vale também aqui, porque plano escrito por agente inventa `arquivo:linha` com a mesma cara de verdade. Referência a arquivo que não existe, ou a linha onde não começa uma definição, é recusa. O checador lê só os arquivos citados, sem catalogar o repo inteiro.
- **D4 — Artefato isolado de propósito se declara no `desfecho: construir`, com o motivo apontando a decisão do design que o isola** — porquê: os relatórios por fundo do caso real são cópias deliberadas, para que a mudança de um fundo não afete o outro. Sem um lugar para declarar isso, o plano ou mentiria "nada equivalente", ou seria forçado a acoplar.
- **D5 — O `revisar` compara só as funções novas do diff com o catálogo do repo, e duplicata HIGH (mesma entrada, mesma saída) reprova** — porquê: rodar o `enxugar` modo 1 inteiro traria apagar, yagni e encolher, que são corte opinativo e poluiriam a revisão. Reprovar só no HIGH evita bloquear por semelhança vaga. MEDIUM e LOW saem como observação, sem reprovar. As funções novas saem de `catalogo-funcoes.cjs` sobre os arquivos do diff, comparadas com o catálogo da base.
- **D6 — O catálogo lê `Method <nome>(...) Class <Classe>` de ADVPL/TLPP como método, com o nome `<Classe>:<nome>`, e o `aviso-duplicata` não muda** — porquê: método de classes diferentes com o mesmo nome (`New`, `Destroy`) não é duplicata, e o aviso de edição gritaria em toda classe. O padrão entra no mapa `metodo` de `hooks/lib/definicoes.cjs`, que o aviso não consulta. Conta a implementação (`Method x() Class Y` na coluna da definição), não a declaração dentro do corpo da `Class`.
- **D7 — Modelo de ameaça: protege contra o agente que planeja ou implementa copiar função existente por não ter procurado ou por não enxergá-la. Fica fora: (a) plano que afirma "nada equivalente" sem ser verdade, que é trabalho do `revisar` (D5) e não do `conferir-busca`; (b) artefato isolado de propósito, declarado no design (D4); (c) o domínio Protheus — onde mora o helper compartilhado, `Static` invisível de outro fonte —, que fica no plugin protheus** — porquê: sem o modelo escrito, cada rodada de revisão acha um vetor novo e a auditoria não converge.
- **D8 — Versão 2.14.0, README e `campo-busca.md` no mesmo commit** — porquê: é capacidade nova e nada quebra para quem já usa. Há duas sessões paralelas em 2.13.3 (`gate-publicacao-gh` e `gate-segmentador`), então a versão é conferida de novo no `fechar` contra a `main` do momento.

## Avaliado e descartado
- **Rodar o `enxugar` modo 1 inteiro no `revisar`** — traz as seis tags e a variação de complexidade. Foi medido no caso real: só `duplicar:` teria mudado o resultado, e o resto é opinião de corte que já tem estágio próprio.
- **Canal `catalogo` só em tarefa que cria arquivo, como o `repo` hoje** — no caso real, nenhuma das 15 duplicatas nasceu em arquivo novo. Seria a mesma trava com o mesmo buraco.
- **Catalogar o repo inteiro dentro do `conferir-busca`** — no template, `listar` com contexto gerou 1 MB para 1.249 funções. Por plano, só os arquivos citados bastam para conferir as referências.

## Fora de escopo
- A réplica no plugin protheus (inventário de reuso no `/protheus:plan`, revisor olhando a pasta da feature, decisão de onde mora o helper) — repositório de trabalho compartilhado, em sessão própria do Luís.
- Aplicar as consolidações achadas no template — é trabalho daquele repositório.
- Duplicata semântica com agente dentro do `conferir-busca` — o sensor é mecânico. O julgamento de intenção fica no `revisar`.

## Varredura
docs/rainforest/varredura/2026-11-13-reuso-antes-de-criar.txt — achou o campo `busca:` (PR #590, lote 1 do apoio ao dev) e o canal `doc` (#667). Isso mudou a parte (2), que ia ser um passo novo do plano e virou ampliação do `busca:` (D2). Achou também a duplicata semântica do `enxugar` (#646) e a complexidade por função (#649, #657), que já são reaproveitadas pelo catálogo. Nenhuma Issue, PR ou branch trata `Method` TLPP nem duplicata no `revisar`. As ideias casadas (`checklist-de-inventario-anterior-no-despacho`, `perguntei-desenho-de-telas-que-ja-existiam`) são de inventário de artefato, não de função, e ficam fora.

## Em aberto
- Nada bloqueia.
