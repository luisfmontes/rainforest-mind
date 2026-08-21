# Statusline versionada no plugin, e os temporarios da bateria de saude

## Objetivo

Tirar a statusline de dentro de `~/.claude` — hoje ela e codigo vivo sem
repositorio, sem historico e sem CI — e fechar o vazamento de `mktemp -d` das
tres secoes de mutacao do `scripts/testa-saude.sh`. Dois trabalhos independentes
na mesma entrega de higiene.

## O que o ambiente disse antes de qualquer decisao

Apurado em 2026-08-20, antes da primeira rodada de perguntas:

- Os **dois** perfis (`~/.claude` e `~/.claude-personal`) apontam para o **mesmo**
  `~/.claude/statusline-command.sh`. A premissa da ideia plantada ("uma copia so
  por acidente de configuracao") estava meio errada: nao ha duas copias
  divergindo. O que ha e o perfil pessoal dependendo de um arquivo dentro do
  config dir de trabalho, e o arquivo que roda nao ter historico nem CI.
- `statusline-jornada.sh` **ja resolve** o problema de achar o plugin sem fixar
  versao: `ls -1t /c/Users/Luis/.claude*/plugins/cache/rainforest-mind/rainforest-mind/*/scripts/jornada.cjs | head -1`.
  O padrao existe e e daqui mesmo — nao precisa ser inventado.
- O CI (`.github/workflows/baterias.yml`) casa **so** `scripts/testa-*.sh` e
  `hooks/testa-*.sh`, roda cada um com `bash`, e falha se achar menos de 15.
  Bateria `.py` nao entra por si so.
- `scripts/testa-saude.sh` tem quatro `mktemp -d`: `SBP` (l.45, coberto pelo
  `trap ... EXIT` da l.46) e `MUTR` (l.269), `MUT` (l.351) e `MUTCD` (l.430),
  os tres removidos por `rm -rf` solto (l.291, l.370, l.446). Interrupcao no meio
  de qualquer um dos tres deixa pasta orfa no temp.

## Decisões fechadas

- **D1 — `statusline.py` e a bateria `testa-statusline-prazo.py` vao para
  `statusline/` no plugin; o `~/.claude/statusline-command.sh` vira resolvedor** —
  porque: o shim passa a ser a unica coisa fora de repositorio (5 linhas, sem
  logica), acha a versao mais nova do plugin nas duas pastas de cache pelo mesmo
  `ls -1t` do `statusline-jornada.sh`, e o `settings.json` dos dois perfis **nao
  e tocado** (o caminho do shim nao muda). Apontar o `settings.json` direto para
  o plugin quebraria a cada bump de versao.

- **D2 — `statusline-jornada.sh` vai junto, na mesma pasta** — porque: e o mesmo
  mecanismo (o `.py` chama o `.sh`), tambem e do rainforest (existe por causa da
  regra 8, le o `jornada.cjs`), e versionar metade deixaria quem mexer amanha
  editando um arquivo com historico e outro sem.

- **D3 — a bateria `.py` entra no CI por um `scripts/testa-statusline.sh` de
  poucas linhas que a invoca** — porque: o glob e o piso de 15 do workflow
  continuam intactos. Mudar o glob para incluir `.py` mexeria na guarda que
  existe para o job nao ficar verde sem provar nada, por causa de um caso so.

- **D4 — o falso positivo residual do prazo se conserta ancorando a data ao
  marcador por proximidade** — porque: hoje qualquer data da linha conta desde
  que a linha tenha marcador, entao `"entrega ate 30/08, conforme combinado na
  reuniao de 22/08"` acende 22/08. So conta data que venha **depois** do
  marcador. O caso novo entra na bateria **antes** da mudanca, e os 8 casos
  atuais tem de continuar passando: se a ancora quebrar qualquer um deles, a
  saida e voltar e reportar, nunca afrouxar o teste.

- **D5 — os tres `rm -rf` avulsos do `testa-saude.sh` viram registro num array
  limpo por um unico `trap ... EXIT`** — porque: fecha os tres de uma vez, e o
  arquivo ja tem um trap global (l.46) que so conhece o `$SBP`; dar trap por
  bloco multiplicaria por tres a chance de o proximo bloco esquecer o dele.

- **D6 — os dois trabalhos numa branch so, um PR so** — porque: nao se tocam
  (`scripts/testa-saude.sh` de um lado, `statusline/` do outro), o plano pode
  marca-los independentes e despachar em paralelo, e dois PRs de higiene na
  mesma noite pagam duas rodadas de CI Windows (minuto vale 2x na cota) para
  provar a mesma arvore.

- **D7 — `~/.claude/statusline.py.bak-antes-prazo-20260818` e apagado depois que
  o arquivo estiver versionado e rodando** — porque: o backup existia por nao
  haver historico; com o `git` no lugar ele e ruido. Apagar so no fim, com a
  statusline ja renderizando pelo caminho novo.

- **D8 — entre errar cedo e nao acender, a barra erra cedo; a ancora por posicao
  fica de fora** — porque: a D4 mandava ancorar a data ao marcador por posicao,
  e a implementacao disso (uma data so conta se ha marcador ANTES dela na linha)
  **matou a ordem inversa**, que e portugues comum: `31/08 e o prazo final de
  entrega do modulo` deixou de acender. Isso e falso **negativo** — o erro que
  esta mesma esteira classificou como o pior, porque alarme cedo o Luis ve e
  descarta, e prazo que nao acende ele so descobre no dia. A ancora trocou um
  erro barato por um caro. Fica so a remocao de clausula de contexto, que e
  puramente subtrativa e nao cria falso negativo.

  **Limitacao aceita, escrita aqui para nao ser redescoberta**: sem a ancora,
  `23/08 e quando o gestor soube do prazo final, que e 31/08` acende 8 dias
  cedo, e o marcador de uma frase ainda vaza para a data da frase seguinte
  (`Prazo final e 31/08. Foi discutido numa reuniao em 23/08.`). Nao ha regex
  que separe `31/08 e o prazo final` de `23/08 e quando soube do prazo final`:
  a diferenca e semantica. Tres rodadas de refino fecharam casos e abriram
  outros; a quarta para aqui de proposito.

## Avaliado e descartado

- **`settings.json` dos dois perfis apontando direto para o caminho do plugin** —
  o caminho carrega o numero da versao (`.../rainforest-mind/0.72.0/...`), entao
  todo `plugin update` quebraria a barra ate alguem editar dois arquivos a mao.
- **Manter a copia de `~/.claude` como a que roda e versionar uma copia no
  plugin** — e exatamente o defeito de 2026-08-10 (duas CLAUDE.md sincronizadas
  a mao, uma divergiu em silencio), so que com codigo.
- **Mudar o glob do CI para casar `testa-*.py`** — o piso de 15 e a guarda contra
  glob quebrado; mexer nela por um caso unico troca uma protecao real por
  conveniencia.
- **Ancora por posicao ("a data so conta se ha marcador antes dela")** — medida
  na rodada 3 e revertida na rodada 4: fecha o caso da data de contexto que vem
  antes do marcador, e em troca **apaga** o compromisso em `31/08 e o prazo
  final de entrega do modulo`. Ver D8.
- **"So a primeira data depois do primeiro marcador"** — regride a linha real
  `- **Projetos 1 — reuniao 17/08, entregar ate 14/08 (sex)**`, onde as duas
  datas tem marcador e o que vale e o menor. Rejeitada antes de ser escrita.
- **Lista literal de conectivos como unica defesa** — a rodada 2 usou
  `conforme combinado|segundo|declarado|citado|mencionado` e so acertava a frase
  exata da bateria: `conforme reuniao`, `de acordo com` e `definido na` erravam
  igual a antes. O conjunto continua existindo, mais largo, mas o design assume
  que ele e **necessariamente incompleto**.

## Fora de escopo

- Reescrever qualquer outro segmento da statusline (git, contexto, rate limit).
  Esta entrega move codigo e conserta um caso de borda do prazo; nao redesenha
  a barra.
- Versionar o resto de `~/.claude` (hooks, settings, agentes). O gatilho aqui foi
  a statusline; varrer o config dir inteiro e outro trabalho, com outro risco.
- Empacotar a statusline como recurso oficial do plugin para outras maquinas
  (registro no `plugin.json`, doc de instalacao). Hoje ela e do Luis; sair para
  outra maquina e o gancho da ideia, nao esta entrega.

## Em aberto

- (nada)
