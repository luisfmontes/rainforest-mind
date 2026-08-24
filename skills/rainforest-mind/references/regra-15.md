# Regra 15 — Ninguém altera o ambiente do usuário.** Agente e janela: sem instalar, PATH,

O worktree da regra 11 isola o
repositório, não a máquina — e a proibição de git destrutivo foi lida como
"cuidado com o repo", deixando a máquina descoberta. Subagente **não**
instala nem desinstala software (`winget`, `npm -g`, `pip`, `choco`), não
mexe em PATH, variável de ambiente, config global nem serviço. Ferramenta
ausente → **para e reporta** o que falta com o comando que resolveria; quem
decide é a janela principal, com a palavra do usuário. O mesmo vale para a
janela principal diante de qualquer instalação: é ação no ambiente, pergunta
antes. E decisão que vive só na cabeça da janela principal não vale — se ela
decidiu não instalar, isso vai **no briefing**.

**Dado fora do repositório é a outra metade de "isola o repositório, não a
máquina", e é a que passa desapercebida.** Diretório de estado do usuário
(`~/.rainforest`, `~/.claude/<coisa>`, cache, banco local) fica **fora** do
worktree: escrever nele é alterar o ambiente do usuário do mesmo jeito que um
`winget` — só que sem instalador nenhum para chamar a atenção. Vale
especialmente para **teste**: teste que só se valida tocando o dado vivo não é
teste de ponta a ponta, é operação em produção. A alternativa é stub, fixture em
pasta temporária ou variável de override; não havendo nenhuma das três, a fatia
**dispensa** o teste e isso vai escrito. E o padrão a barrar por nome é
**backup-e-restaura em cima do dado real** — ele parece cuidadoso e transfere o
risco para o `finally` funcionar.

E o mecanismo não pega isto: o `conferir-entrega.cjs` confere **git**, então dano
fora do repositório passa pelas cinco checagens. Aqui a rede é a regra 12 pela
aritmética — número que não fecha no relato é gatilho de auditoria.

> 2026-08-12, projeto de plugins de uma squad, tarefa 6 de um plano de 13: a
> regra do projeto ("teste não pode ler dado vivo") entrou no briefing em prosa,
> sem o caminho — nas tarefas 4 e 5 ele tinha sido nomeado. O agente fez
> `Copy-Item` do diretório de estado real, sobrescreveu com fixture e restaurou
> num `finally` que não funcionou: dois arquivos reais (medição de horas e um
> cache de enriquecimento) ficaram com conteúdo de teste, e o relato dizia
> sucesso. As 5 checagens do `conferir-entrega` passaram, porque o dano foi fora
> do git. O que pegou foi um "803 passed, 17 skipped" que não fechava com o
> esperado, e o snapshot que o próprio projeto já tinha recuperou a medição sem
> perda.

> 2026-08-08: dos 12 agentes que destilaram livros para o vault, um precisou
> converter um PDF escaneado em imagem e instalou o Poppler via winget por
> conta própria — a janela principal tinha decidido justamente o contrário,
> mas isso vivia só na cabeça dela. Saiu bem, e mesmo assim é mudança no
> computador dele sem a palavra dele, descoberta só no relatório final.

**Inspecionar ambiente nunca por dump filtrado.** Para ver o que está
setado, use `printenv NOME` para nomes específicos ou `compgen -e`, que só
devolve nomes por construção. `printenv | cut -d= -f1` **parece** seguro e
não é: valor multilinha (PEM, JSON, certificado) tem linhas sem `=`, e o
`cut` as deixa passar inteiras. Assuma que todo valor de env pode ser
multilinha.

> 2026-08-09: `printenv | cut -d= -f1`, pedido justamente para não expor
> valores, deixou passar o corpo base64 de uma chave privada Ed25519 — a
> chave inteira — para dentro de um print que o usuário colou na conversa.
> Chave rotacionada, print apagado, sem impacto em cliente.
