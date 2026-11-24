## Resumo

Três erros que apareciam no uso. Versão 2.17.2.

```
integrar-tarefa      git() com maxBuffer de 1 GiB; recusa mostra res.error (ENOBUFS)          #731
gate-pergunta-memo   palavra com barra (caminho, branch) sai da pergunta antes de contar termos  #730
gate-publicacao      visibilidade pela URL de PUSH (no_push não conta); mensagem nomeia o remoto  #723
                     declaradaPrivada segue olhando o fetch (push desligado não abre a declaração)
```

## Evidência

- **Antes** (bateria nova contra o código da base, rodada pelo revisor): integrar `ok: 78 falhou: 3` (seção #731 recusa em `diff`); pergunta-memória `ok: 23 falhou: 2` (P25 e P26 saem 2); publicação: `723 mensagem nomeia o upstream` e `723 upstream com push no_push passa` falham.
- **Depois**, no HEAD desta branch:
  - `bash scripts/testa-integrar-tarefa.sh`: `ok: 81   falhou: 0`
  - `node hooks/testa-gate-pergunta-memoria.cjs`: `ok: 25   falhou: 0` (P1, o caso de origem, segue exit 2)
  - `bash hooks/testa-gate-publicacao-destino.sh`: `== resultado: 310 ok, 0 falha(s) ==`
  - `conferir-fluxo.cjs mutacoes`: tarefas 1, 2 e 3 vermelhas; 4 n/a.

Duas rodadas de revisão independente; a 1ª aprovou com um achado médio (a declaração de privado passava a valer com o push desligado), consertado aqui e aprovado na 2ª.

## Perigo de merge

**Porta:** mão dupla. Um script e dois hooks; um revert devolve o comportamento anterior.
**Raio de impacto:** pequeno. O gate de publicação muda só a leitura de remotos (push em vez de fetch) e a mensagem; o de pergunta só tira palavra com barra; a integração só ganha buffer.

## Deixado para depois

nada ficou para depois

Fora desta rodada:
- **#722** e **#724** ficam abertas: furos de cobertura achados em revisão, não erro que aparece no uso. A #722 pede mecanismo novo (seguir o arquivo por `cp`/`mv`/`<`, ler spawn em array) e a #724 pede bateria de cada gate que usa `hooks/lib/heredoc.cjs` e revisão de segurança própria (D4 do design).
- Resíduos aceitos (`[baixa]`): regex de URL do GitHub sem barra final/`git://`/porta (preexistente), `repositoriosDoGitHub` sem chamador, sugestão de declarar sem teste próprio. Estão no design.

## Decidido sem você
- D2: tirar da pergunta codigo inline e kebab, ou so a forma de caminho? → So a forma de caminho/branch (barra). Porquê: codigo inline e kebab fora derrubavam o P1, o caso de origem; a #730 tem barra
- D3 (revisão 1): `declaradaPrivada` olha também a URL de fetch, para o push desligado não abrir a declaração de privado; a frase do design sobre um gate de push, que não existe, saiu.

Closes #731, closes #730, closes #723.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
