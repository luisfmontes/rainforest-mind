# Pendência do fluxo só sai com destino (#449)

## Objetivo
Uma pendência gravada em `pendentes` no estado do fluxo não pode sumir em silêncio. Quando o estágio
fecha `ok`/`aprovado`, cada pendência precisa de um destino: foi resolvida, foi plantada ou foi
descartada. O `fechar` lista esses destinos no corpo do PR. Assim, "deixado para depois" tem resposta
quando o fluxo fecha.

## Decisões fechadas
- **D1 — Destino no `--json`, casado pelo texto** (Q2 A, 2026-10-09) — o campo novo `destinos` é uma
  lista de `{pendente, destino, evidencia|ref|motivo}`. `pendente` é o texto exato de uma string de
  `pendentes`. As `pendentes` continuam strings, e nenhum arquivo de estado migra.
- **D2 — Três destinos, cada um com seu campo obrigatório:**
  - `resolvida` exige `evidencia` não vazia.
  - `plantada` exige `ref` no formato `#<n>`, URL de issue do GitHub (`https://github.com/<dono>/<repo>/issues/<n>`)
    ou `ideia:<id>`. O id da ideia não é conferido contra o `ideias.jsonl`, que mora fora do repositório.
    O formato é a trava.
  - `descartada` exige `motivo` não vazio.

  Destino fora dos três, campo faltando, ou `pendente` que não casa com nenhuma pendência do bloco: o
  `marcar` recusa com exit 2 e diz o item.
- **D3 — `ok`/`aprovado` recusa pendência sem destino.** No `marcar` com status terminal-positivo, as
  pendências são a união das do bloco anterior com as do `--json` novo. Se alguma não tiver destino
  (contando os destinos acumulados e os novos), o `marcar` recusa com exit 2 e lista as que faltam. Com
  todas destinadas, `pendentes` some como hoje (`CAMPOS_EFEMEROS`, PR #54: estado completo não lista
  pendência), e `destinos` fica.
- **D4 — `destinos` acumula e não é efêmero.** A fusão do `marcar` é rasa. O `destinos` do `--json` novo
  é somado ao do bloco anterior, e o destino mais novo de uma pendência substitui o antigo. O campo
  sobrevive ao `ok` para o `fechar` lê-lo.
- **D5 — `parcial` que omite pendência avisa.** Em status não terminal, se o `--json` traz `pendentes` e
  alguma pendência anterior sem destino não está na lista nova, o stderr diz qual sumiu. A gravação
  continua sem recusa. A pendência omitida volta a contar como pendente: ela entra numa lista
  `pendentes` mantida pela união com a anterior, em vez de ser apagada. Só um destino a tira da lista.
- **D6 — O `fechar` recusa e lista.**
  - `exigir --estagio fechar` recusa com exit 2 se qualquer estágio ainda tiver pendência sem destino.
    Isso é defesa para arquivo antigo ou editado à mão, porque o D3 já barra o caminho normal.
  - O verbo novo `estado.cjs deixado --slug <s>` imprime em markdown a lista "deixado para depois →
    destino" de todos os estágios, ou `nada ficou para depois`.
  - `skills/fechar/SKILL.md` manda colar essa saída no corpo do PR.
- **D7 — Contrato documentado.** A seção "Condição de parada" de `skills/executar/SKILL.md` explica o
  `destinos`, e o CHANGELOG traz a mudança. A versão sobe para MINOR, 1.55.0, porque o contrato muda.

## Avaliado e descartado
- **Pendência vira objeto com id (Q2 B):** obrigaria migrar quem grava hoje e os 12 arquivos de estado
  com `pendentes`.
- **Painel do mod grava no estado do fluxo (Q1 A):** os itens vêm de um segundo modelo lendo o relato.
  Numa trava que recusa o `ok`, um falso positivo bloqueia o fluxo. Isso vira uma issue própria, depois
  de medir o ruído do painel.
- **Conferir `ideia:<id>` contra o `ideias.jsonl`:** o arquivo mora em `~/.rainforest`, e as baterias
  não tocam essa pasta. A trava fica no formato.

## Fora de escopo
- Integração do painel "Deixado para depois" (`hooks/mod.tsx`) com o estado. Vira issue nova ao fechar.
- `reaberto_por` e `em_voo`, que continuam efêmeros como hoje.

## Varredura
`docs/rainforest/varredura/2026-10-09-pendente-destino.txt`. Dos resultados, o PR #54 criou o
apagamento de `pendentes` no `ok`. O motivo dele (estado completo não lista pendência) segue valendo,
e o D3 o mantém. A #424 e o PR #425 tratam do painel do mod, que fica fora de escopo. Os demais
casaram por palavra em outro sentido.

## Em aberto
Nada. Q1 e Q2 foram fechadas na rodada de 2026-10-09.

## Critério de pronto
- `marcar --status ok` num bloco com `pendentes` e sem `destinos` dá exit 2 e lista as pendências.
- Com destino para cada uma, dá exit 0. O bloco fica sem `pendentes` e com `destinos`.
- `plantada` sem `ref` válida, `resolvida` sem `evidencia` e `descartada` sem `motivo` dão exit 2.
  `pendente` que não casa também dá exit 2.
- `parcial` que omite uma pendência anterior mostra o nome dela no stderr, e ela continua em `pendentes`.
- `exigir --estagio fechar` com pendência sem destino num bloco editado à mão dá exit 2.
- `deixado --slug` lista os destinos em markdown.
- Uma mutação que volta o D3 ao apagamento silencioso deixa a bateria vermelha.
