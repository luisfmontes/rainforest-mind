# Regra 14 — Regra bloqueada pelo ambiente se anuncia.** Ambiente que impede uma regra de

**O transporte da regra também é ambiente:** o que não coube na injeção está
bloqueado, e quem detecta isso é o emissor ou o teste, **nunca o texto
injetado** — o texto que foi cortado não tem como saber que foi. Esta frase vive
aqui, e não no núcleo, porque ela é instrução para quem **mantém** o arquivo:
custava 190 B em toda sessão, e foram esses bytes que faltaram, em 2026-08-11,
para o prazo de sexta caber na abertura.

Quando o ambiente da sessão
(configuração do harness, permissão negada, MCP fora do ar, plugin ausente)
impedir uma regra desta skill ou do CLAUDE.md global de valer, **dizer em uma
linha na primeira vez que ela seria aplicada** — nunca seguir em silêncio
pelo caminho alternativo. Silêncio faz o usuário acreditar que a regra rodou.
Mesma família da ronda de vigia que falha na pré-checagem e não relata:
**silêncio ≠ nada a relatar**.

> 2026-08-08: a sessão carregava instrução do harness proibindo chamar o
> Agent; a regra 10 ficou desligada a sessão inteira e a coleta de uma
> análise inteira rodou na janela principal, gastando contexto à toa — o
> o usuário descobriu perguntando, não pelo aviso.

O aviso é uma linha só, com o efeito prático
nomeado ("a regra 10 está bloqueada nesta janela: despacho só se você
pedir"), e não se repete na mesma sessão.

**Aviso de bloqueio vem antes da execução, e oferece a saída.** Quando a
regra bloqueada for a 10 (despacho de subagente) e a task for **grande** —
critério duro, sem julgamento de estilo: toca mais de um arquivo ou
repositório, ou passa de umas poucas chamadas de ferramenta —, o aviso
**para o turno** e devolve a escolha: "a regra 10 está bloqueada nesta
janela e isso ia gastar contexto aqui — você libera o subagente ou faço
inline?". Trabalho grande não começa antes da resposta dele. Task pequena,
onde perguntar custa mais que fazer, segue com o aviso de uma linha. O
aviso **sempre nomeia a saída**, porque ela é uma frase dele: "pode liberar
subagente". Anunciar sem parar é anunciar tarde.

> 2026-08-08, na mesma sessão em que a regra nasceu: o aviso saiu na
> primeira linha do turno e a execução saiu junto, sem esperar — validar
> duas ideias virou leitura de dois repositórios inteiros na janela
> principal, e a chance de liberar o subagente chegou depois do trabalho já
> feito.

**Caminho de ambiente se resolve pela variável, nunca se escreve à mão.**
Cache de plugin, config, sessão: a raiz é a `CLAUDE_CONFIG_DIR` **desta**
sessão, resolvida na hora. Caminho fixo no texto envelhece calado, e é o
modo de falha desta família: não dá erro, devolve o número de um plugin que
nem está carregado.

> 2026-08-08: a variável passou de `.claude` para `.claude-personal` e a
> pasta velha ficou com versões obsoletas (1.12.0 contra 1.16.0 na nova); a
> regra 8 apontava pra ela.

Ambiente que mudou de lugar
bloqueia regra do mesmo jeito que ambiente ausente, e pede o mesmo aviso.

**Tool que falta se confere no init da sessão, nunca perguntando ao modelo.**
Modelo sem uma tool **inventa a causa** em vez de dizer "não tenho": ele
produz uma explicação plausível — OAuth vencido, sessão não-interativa,
credencial sem refresh — que passa por diagnóstico e manda a investigação
para o lado errado. A verdade de máquina sai de
`claude -p --output-format stream-json --verbose`, no evento `system/init`:
ele lista cada MCP com `connected` / `disabled` / `pending` / `needs-auth` e
os nomes de tool registrados. `claude mcp list` **não serve** para isso —
ele testa o servidor, não a sessão, e diz `✔ Connected` para servidor
desligado no projeto.

> 2026-08-10: os vigias pararam de fazer a triagem de inbox e o sentinela
> registrou "Gmail MCP nao autenticado em sessao nao-interativa" no
> `ERROS.md` — frase inventada pelo próprio vigia. A credencial estava boa
> (o refresh contra o Google devolveu HTTP 200 na hora). O `init` mostrou
> `status: disabled`, e a causa era uma linha em `.claude.json`:
> `projects["C:/Projetos/rainforest-mind"].disabledMcpServers` com
> `["github","playwright","whatsapp","gmail"]` — só neste projeto. Dois
> modelos seguidos repetiram a explicação de OAuth, o segundo já citando a
> observação errada que o primeiro tinha gravado na memória.

**Mídia do WhatsApp que o bridge não baixa costuma estar em `Downloads`.**
O cliente desktop salva o que chega, então o caminho local existe mesmo
quando o `download_media` falha — perguntar o caminho ao usuário vem antes de
insistir no bridge. Em 2026-08-10 o bridge devolvia 403 para **toda** mídia,
inclusive uma de 14 minutos atrás, então não é expiração.
