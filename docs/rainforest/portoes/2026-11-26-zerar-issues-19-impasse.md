# Impasse — 2026-11-26-zerar-issues-19 (revisar)

## O que travou

O `revisar` reprovou três voltas, e o teto do estágio é 3. Cada volta achou uma forma nova da mesma família: o comentário depois de um movedor (`cd`, `pushd`, `Set-Location`...) marcava a linha como incerta, ou deixava de marcar:

1. **Primeira volta [media]:** `\s+#` aceitava `\ #` e NBSP como início de comentário. O conserto foi `(?<![\\`])[ \t]+#`. Depois disso, a revisão de segurança mostrou que no PowerShell a contrabarra é literal, e vieram os conjuntos por dialeto (`paraPowerShell`) e o fallback "dialeto desconhecido = incerto".
2. **Segunda volta [media]:** um parêntese dentro do comentário marcava subshell. O conserto foi o grupo de captura do comentário e o incerto na leitura antiga.
3. **Terceira volta [media]:** formas com prefixo ou redirecionamento (`command cd`, `\cd`, `2>&1`) e a linha só de comentário. O conserto foi normalizar primeiro e deixar neutra a linha só de comentário na leitura nova. A revisão de segurança do commit levou ao `inicioDoComentarioCru`.

A quarta volta já rodou no head `bd07a644` e deu `VEREDITO: ok`, com três achados `[baixa]`:

- a linha neutra, sem exit novo;
- `cd -P/-L` e `pushd --`, furo anterior, de outro mecanismo, que vira Issue própria;
- os falsos positivos D3, já declarados.

## Opções postas ao usuário (2026-11-27)

- **A (recomendada):** liberar a volta extra, que já aprovou, e seguir para verificar e fechar.
- **B:** reduzir o escopo ao gate de bateria e devolver o `cd #comentário` para a #736.
- **C:** encerrar sem merge.

## Decisão

O usuário respondeu "recomendado", ou seja, a opção A. A rodada extra é a quarta volta, já executada, com veredito ok sobre `b76d80f8..bd07a644`.
