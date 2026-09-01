# Validação externa do conselho — rodada real com 5 membros (T9)

2026-08-31, Windows 11, máquina do Luís. CLIs: codex-cli 0.151.0 (oauth
ChatGPT Plus, motor gpt-5.6-sol), gemini-cli 0.57.0 (GEMINI_API_KEY do AI
Studio, modelo fixado gemini-3.7-flash), claude CLI local. Chaves
`conselho-codex` e `conselho-gemini` ligadas por config de projeto no sandbox.

## Questão real

`questao-multi-rodada.md`: o conselho deve ganhar debate multi-rodada quando a
síntese acumular divergências recorrentes? (A: manter tiro único; B: segunda
rodada condicional; C: convergência iterativa) — a decisão que o próprio
design do fluxo 11 deixou marcada como "reavaliar".

## Fase 1 — pareceres (5 membros reais)

```
$ node .../conselho.cjs abrir --questao questao-multi-rodada.md
Rodada 20260831-questao-multi-rodada aberta
Membros: cetico, arquiteto, usuario-final, codex, gemini
[abrir exit=0]

$ node .../conselho.cjs pareceres
Pareceres coletados de 5 membros
[pareceres exit=0]
$ node .../conselho.cjs conferir --fase pareceres
[conferir exit=0]
```

Posições: A = cetico, **codex**, **gemini**; B = arquiteto, usuario-final.
Divergência genuína entre famílias de modelo, colhida na primeira rodada.

## Fase 2 — indisponibilidade REAL e falha fechada (D9 ao vivo)

O free tier do gemini estava sob carga (503 "high demand" na API crua, 429
intermitente). Duas execuções de `revisar` reprovaram **sem prosseguir com
4/5**:

```
  gemini: timeout ou erro de execução
[revisar exit=1]
Revisão inválida: gemini: revisao não encontrada
[conferir revisao exit=1]
```

Retentativa pelo contrato de membro (só o faltante), 90s de intervalo:

```
--- tentativa 1 (22:31:06) ---
adaptador-gemini: exit 1
--- tentativa 2 (22:32:40) ---
REVISAO GRAVADA
[portao revisao OK]
```

Anonimização conferida na rodada real: `grep -rE 'cetico|arquiteto|usuario-final|codex|gemini' fase2/`
(fora o mapa interno) não casa nada.

O contador de tentativas da fase marcou 2 e **zerou no sucesso**
(sucesso-zera-contador na prática); a 3ª reprovação teria gravado ABANDONA.

## Fase 3 — síntese mecânica

```
$ node .../conselho.cjs sintetizar
Síntese gravada em .../sintese.json
[sintetizar exit=0]
$ node .../conselho.cjs conferir --fase sintese
[portao sintese exit=0]
```

`sintese.json` anexado em `relatorios/2026-08-31-conselho-sintese-rodada-real.json`
— 4 campos, `ranking_agregado` com os **5 nomes reais** desanonimizados
(`cetico, arquiteto, usuario-final, codex, gemini`), `divergencias_nao_resolvidas`
não vazio, gravada **sem** `--unanime`. Decisão recomendada: **A — manter o
tiro único** (o conselho recomendou contra expandir a si mesmo).

## Cenário de indisponibilidade por chave ausente (critério do plano)

```
$ env -u GEMINI_API_KEY node .../conselho.cjs adaptador-gemini <prompt> <saida>
adaptador-gemini: GEMINI_API_KEY não definida no ambiente — gemini CLI exige credencial
[exit=1]
arquivo de saida NAO criado (falha fechada ok)
```

## Defeitos que SÓ a rodada real revelou (todos corrigidos e commitados)

| defeito | commit |
|---|---|
| prompts sem schema JSON (modelo real responde prosa); cerca de código; timeout fixo 30s | b451c7a |
| adaptadores mandavam o CAMINHO do arquivo como pergunta; validavam revisão como parecer | 2750f9a |
| cmd padrão dos adaptadores com caminho relativo ao repo do plugin | c48ef85 |
| sintetizar lia parecer/revisão com JSON.parse cru (cerca derrubava a fase 3) | f3fe0f1 |

Nenhum era visível por fixture — as 62 baterias estavam verdes antes e depois.

## Aberto (para o revisar)

- `fases.*.status` do estado da rodada nunca sai de "pendente" — os portões
  zeram tentativas no sucesso mas não marcam a fase como fechada.
  **[RESOLVIDO — T11: portão marca status='ok' ao passar]**
- Instabilidade do free tier do gemini (503/429) faz a fase 2 custar
  retentativas; a falha fechada segura, mas o operador precisa retentar por
  membro para não queimar o teto de 3 do portão.
  **[RESOLVIDO — T12: flag --membro <nome> reexecuta só esse]**
