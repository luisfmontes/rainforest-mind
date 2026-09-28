# Gate: subagente não escreve no GitHub (direto nem por script)

## Objetivo
Impedir, por mecanismo, que um subagente escreva no GitHub com `gh` — no comando
direto, dentro de wrapper de string, em heredoc ou dentro de um script que ele
mande executar. Duas vezes (2026-09-13, `zerar-issues-3`; 2026-09-28,
`zerar-issues-10`) um revisor rodou `gh issue close 12` real com a proibição
escrita no briefing; a regra em prosa não segura.

## Decisões fechadas
- **D1 — Hook novo `hooks/gate-subagente-sem-gh.cjs`, `PreToolUse` de `Bash`, só age com `agent_id` no payload (subagente); a janela principal passa sempre. Toggle `subagente-sem-gh` em `hooks/lib/config.cjs`, padrão ligado, mesma forma de `bateria-sem-timeout`** — porquê: decisão do usuário (Q1 (c), Q2) em 2026-09-28; fechar issue e abrir PR são da janela principal, no `fechar`, então subagente não tem uso legítimo.
- **D2 — "Escrita" é: `gh issue close|comment|edit|create|reopen|delete|transfer|pin|unpin|lock|unlock`, `gh pr create|edit|merge|close|comment|reopen|review|ready`, `gh release create|edit|delete|upload`, `gh repo create|edit|delete|rename|archive`, `gh label|secret|variable` com `create|edit|delete|set`, `gh workflow run|enable|disable`, `gh run rerun|cancel|delete`, e `gh api` com `-X`/`--method` diferente de `GET` ou com `-f`/`-F`/`--field`/`--raw-field`/`--input` sem `-X GET`; leitura (`view`, `list`, `status`, `checks`, `diff`, `api` GET) passa** — porquê: `gh api` com campo vira POST por padrão; o resto é a lista de subcomandos que mudam estado remoto.
- **D3 — O comando direto é lido com a lib comum (`tokensComAspas`, `posicaoDeComando`, wrappers que repassam, `desempacotarWrapperDeString`) e o token comparado sem contrabarra e com escapes ANSI-C resolvidos, como o `gate-fechar-issue` faz desde a 1.27.0; wrapper de string ilegível (`bash -c "$x"`, `eval "$x"`) dentro de subagente é negado; corpo de heredoc é varrido como texto pelo mesmo padrão** — porquê: são as três formas pelas quais o `gh` já escapou de gate neste repo (#313, #339, heredoc criando o script no mesmo comando). *(Extensão de Q2, confirmada pelo usuário em 2026-09-28.)*
- **D4 — Script executado é lido antes de rodar: quando o segmento executa um arquivo (`bash|sh|source|.|exec <arq>`, caminho direto `./x.sh`, `node|python <arq>`), o gate lê o arquivo (resolvido contra o cwd efetivo do segmento) e nega se alguma linha não comentada casar com o padrão de escrita de D2 — tanto a forma de shell (`gh issue close`) quanto a de chamada (`'gh', ['issue', 'close'` / `"gh", "pr", "merge"`); arquivo que não existe ou não se lê passa** — porquê: o incidente de 2026-09-28 foi exatamente `bash script.sh` com o `gh` dentro; ler o arquivo é o que o gate consegue ver sem executar.
- **D5 — Isenção: arquivo de nome `testa-*` rastreado pelo git no repo dele (`git ls-files --error-unmatch`, o que inclui o que só está no stage), mesmo alterado, não é varrido — as baterias citam `gh issue close` como texto de teste e usam stub próprio; arquivo não rastreado nunca é isento (a mensagem diz para dar `git add` antes de rodar uma bateria nova); exceção à isenção: `scripts/fechar-issue.cjs` é negado pelo nome em subagente, porque é o fechador oficial** — porquê: sem a isenção o subagente não roda bateria nenhuma, e com "sem alteração" o executor não roda a bateria do gate que está consertando; o script avulso em pasta temporária dos dois incidentes continua lido e barrado; sem a exceção a isenção abre a porta pelo próprio script do fluxo. *(Extensão de Q2 — `fechar-issue.cjs` — e forma da isenção, "rastreado mesmo alterado" no lugar de "sem alteração", confirmadas pelo usuário em 2026-09-28.)*
- **D6 — Mensagem de bloqueio diz o que foi visto (comando ou arquivo:linha), que escrita no GitHub é da janela principal, e como medir o gate sem executar `gh` (payload JSON no stdin do hook); uma linha em `referencias/perfil-de-trabalho.md` explica a regra aos agentes, aplicada com `node scripts/perfil.cjs --aplicar`; README (lista de hooks), CHANGELOG e versão minor acompanham** — porquê: Q1 (c) — o gate barra, o texto explica o porquê para o agente não procurar desvio.

## Avaliado e descartado
- Só a regra em prosa no briefing: falhou duas vezes (2026-09-13 e 2026-09-28), medido pelos incidentes.
- Isenção só para arquivo versionado sem alteração: todo fluxo que mexe em gate edita a bateria dele (`testa-gate-fechar-issue.sh` cita `gh issue close` centenas de vezes), e o executor ficaria impedido de rodá-la.
- Isenção pelo nome `testa-*`, rastreado ou não: bastaria chamar o script avulso de `testa-x.sh`.
- Executar o comando num shell isolado para ver o que roda: efeito colateral dentro do hook, e a #337 já mostrou o custo de modelar o bash.

## Fora de escopo
- Janela principal: continua livre (o `gate-fechar-issue` já cobre o fechamento sem evidência).
- Escrita no GitHub por outro meio que não `gh` (`curl` na API, `git push`): `git push` de branch própria é parte do trabalho do agente em alguns fluxos; `curl` com token não aparece em nenhum incidente.

## Em aberto
(nenhum)
