## Fora desta rodada

- **#722** (staging em massa por script não-shell via spawn em array, `sh < arquivo` ou cópia) e **#724** (máscara de heredoc ignora continuação de linha) ficam abertas. As duas são furos de cobertura achados em revisão, não erro que aparece no uso. A #722 pede mecanismo novo (seguir o arquivo por `cp`/`mv`/`<`, ler spawn em array) e a #724 pede bateria de cada gate que usa `hooks/lib/heredoc.cjs` e revisão de segurança própria (D4 do design).
