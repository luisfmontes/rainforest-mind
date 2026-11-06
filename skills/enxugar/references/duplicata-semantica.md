# Duplicata semântica — prompts das fases de modelo

Detalhe da passada de duplicata semântica do modo 2 do `enxugar`. O `SKILL.md`
diz a ordem das fases; aqui ficam os dois prompts e o formato que a fase de
conferência espera. Ideia enxertada de `obra/superpowers-lab`
(`skills/finding-duplicate-functions`, MIT), reescrita para o catálogo do
`scripts/catalogo-funcoes.cjs`.

## Fase 2 — categorizar (agente haiku)

Um agente só, barato: agrupar não exige julgamento fino.

```
Leia o catálogo de funções em <CAMINHO>/catalogo.json (array de
{arquivo, linha, nome, assinatura, contexto, linguagem}).

Dê a cada função exatamente UMA categoria, pelo propósito principal:

- arquivo: ler, gravar, caminho, pasta
- texto: formatar, analisar, sanitizar, converter caixa, truncar
- validacao: checar entrada, schema, guarda de tipo, asserção
- erro: criar, embrulhar, formatar, registrar erro
- http: montar requisição, ler resposta, URL, cabeçalho
- data-hora: formatar, analisar, comparar, fuso
- transformacao: mapear, filtrar, normalizar, serializar
- banco: consulta, conexão, migração
- log: formatar log, depuração, telemetria
- config: carregar configuração, variável de ambiente
- assincrono: promessa, retentativa, debounce, throttle
- interface: widget, componente, evento de tela, navegação
- estado: store, provider, controller, cache em memória
- cripto: hash, cifra, token
- autenticacao: login, sessão, permissão
- outros: não cabe acima (diga a subcategoria no propósito)

Grave em <CAMINHO>/categorizado.json um array com, para cada função:
{"arquivo": "...", "nome": "...", "linha": N, "category": "...", "purpose": "uma frase"}

Copie arquivo, nome e linha do catálogo sem mudar nada. Não invente função.
```

## Fase 4 — comparar (um agente sonnet por categoria)

Um agente por arquivo de `separar`, em paralelo. É a fase que exige
julgamento: duas funções com nomes diferentes podem fazer a mesma coisa, e duas
com nomes parecidos podem não fazer.

```
Você compara as funções da categoria "<CATEGORIA>", em
<CAMINHO>/<CATEGORIA>.json, atrás de duplicata semântica: funções que servem
ao MESMO PROPÓSITO mesmo com nome, implementação ou assinatura diferentes, ou
quando uma é a forma geral da outra.

Para ler a implementação inteira, abra o arquivo na linha indicada.

Devolva em <CAMINHO>/grupos-<CATEGORIA>.json um array de grupos:

[
  {
    "intent": "<o que todas fazem>",
    "confidence": "HIGH|MEDIUM|LOW",
    "functions": [
      {"file": "<arquivo do catálogo>", "name": "<nome>", "line": <linha do catálogo>, "notes": "<o que a implementação tem de próprio>"}
    ],
    "differences": "<como diferem, se diferem>",
    "recommendation": {
      "action": "CONSOLIDATE|INVESTIGATE|KEEP_SEPARATE",
      "survivor": "<se CONSOLIDATE, o name exato de uma das functions acima>",
      "reason": "<por quê>"
    }
  }
]

Confiança:
- HIGH: mesma entrada dá a mesma saída. Ex.: formatarData(d) e dataParaTexto(d)
  formatam igual.
- MEDIUM: mesmo propósito com diferença menor. Ex.: validarEmail com regex e
  checarEmail com biblioteca.
- LOW: talvez relacionadas. Ex.: sanitizar(s) e escaparHtml(s).

Regras:
- Na dúvida, INVESTIGATE, nunca CONSOLIDATE.
- Compare o tratamento de borda (nulo, vazio, erro): é onde "iguais" divergem.
- Utilidade genérica (identidade, noop, constante) costuma ser duplicada de
  propósito: KEEP_SEPARATE.
- file, name e line saem do catálogo, copiados. Função fora do catálogo será
  descartada pela conferência.
```

## Fase 5 — o que a conferência faz

`catalogo-funcoes.cjs conferir --catalogo catalogo.json --grupos grupos-<CATEGORIA>.json`
confere cada função de cada grupo contra o catálogo (mesmo arquivo, nome e
linha). Os grupos válidos saem no stdout. Cada função inválida é nomeada no
stderr, e o exit é 1 quando há qualquer uma — aí o grupo dela não vira achado,
e a categoria se relata com o número de grupos descartados. Grupo com menos de
duas funções distintas também é descartado e sai 1, com `grupo N: ...` no
stderr. CONSOLIDATE cujo `survivor` não é o `name` de uma função do grupo sai
no stdout rebaixado para INVESTIGATE, com aviso no stderr e exit 0: leia o
stderr antes de contar os `duplicar:`.
