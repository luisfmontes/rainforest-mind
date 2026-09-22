# Rodando sozinho, sem babá

O loop longo autônomo é feito com o `/loop` **nativo do Claude Code** — esta
skill não implementa motor nenhum, e não precisa. O que ela adiciona ao `/loop`
é justamente o que falta nele: uma condição de saída que não é "o usuário
mandou parar".

`/loop` sem régua e sem teto é queima de token com aparência de progresso. Com
os dois, é a única configuração em que largar e sair de perto se sustenta.
