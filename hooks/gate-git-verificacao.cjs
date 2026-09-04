#!/usr/bin/env node
/**
 * PreToolUse — barra pulo de verificacao no git.
 *
 * O executor de um fluxo do rainforest-mind e quem mais tem motivo para pular
 * hook de commit quando ele reprova: e o proprio executor que escreveu o codigo
 * que o hook esta reprovando, e `--no-verify` remove a fricção na hora exata em
 * que ela importa. Texto de skill dizendo "nao use --no-verify" nao alcanca esse
 * modo de falha — exit code alcanca (mesmo raciocinio do `gate-staging-total`,
 * tarefa 2 do plano `docs/rainforest/planos/2026-09-04-nao-mente.md`, D8-D11).
 *
 * O QUE ESTE GATE E, E O QUE NAO E — declarado aqui depois de tres rodadas de
 * ataque, porque ficar implicito ja causou confianca em cobertura que o gate
 * nao tem:
 *
 * Isto e um QUEBRA-MOLAS contra o atalho, nao uma FRONTEIRA contra evasao
 * deliberada. Ele existe porque quem executa um fluxo chega em `--no-verify`
 * por CONVENIENCIA no momento em que o hook de commit reprova — nao porque
 * alguem vai ofuscar o comando de proposito para escapar de uma trava que
 * nem sabe que existe. O gate reduz o atalho automatico; ele nao foi
 * desenhado, e nao seria vencedor, contra quem monta o comando de proposito
 * para passar por baixo dele.
 *
 * Prova disso: um PARSER DE SHELL ESCRITO A MAO NUNCA GANHA a corrida contra
 * ofuscacao. Isto e fato medido neste arquivo, nao suposicao — tres rodadas
 * de ataque, forma nova a cada uma:
 *   - rodada 1, 2026-09-04 (security review de fundo, commit 7d0fb268): flag
 *     citada de tres formas (aspas simples, duplas, coladas: `--no-"verify"`),
 *     abreviacao de long option que o git aceita (`--no-veri`), separador `&`
 *     solto, prefixo nao reconhecido antes do `git` (`then`), substituicao de
 *     comando `$(...)`, linha continuada com `\` + quebra de linha;
 *   - rodada 2, 2026-09-04 (commit fb713c3): `bash -c "..."`, `sh -c '...'`,
 *     subshell `(...)`, flag combinada (`bash -lc`) e aninhamento simples;
 *   - rodada 3, 2026-09-04: nome de shell com caminho na frente (`/bin/bash`,
 *     `/bin/bash.exe`), `eval`, escape por barra invertida (`--no\-verify`)
 *     e aspa dupla escapada dentro de shell aninhado;
 *   - rodada 4, 2026-09-04 (revisor independente): variacao de CAIXA no nome
 *     do executavel (`GIT`, `Git`, `gIt`, `BASH`, `Bash`) — em sistema de
 *     arquivos case-insensitive (NTFS/Windows, o padrao do Git Bash) o SO
 *     resolve `GIT` para o mesmo binario de `git`, e so a tecla Shift
 *     bastava para contornar o gate.
 * Quatro rodadas de EVASAO (deixar `--no-verify` passar sem ser pego), forma
 * nova a cada uma. Nao ha razao para crer que uma quinta rodada de evasao
 * nao acharia uma sexta forma — e e por isso que este bloco declara o limite
 * em vez de prometer cobertura completa.
 *
 * RODADA 5, 2026-09-04 (revisor independente): FALSO POSITIVO, categoria
 * oposta das quatro acima — em vez de deixar passar, o gate BARRAVA trabalho
 * legitimo. `segmentos()` fatiava o comando bruto por quebra de linha antes
 * de saber que uma faixa dele era CORPO DE HEREDOC (dado — mensagem de
 * commit, conteudo de arquivo — nunca comando), e mandava cada linha do
 * corpo para `analisaComando` como se fosse codigo. Um heredoc que so
 * MENCIONA `--no-verify` em prosa (`cat > docs.md <<EOF` / texto citando a
 * flag / `EOF`) barrava um comando que nao invoca `git` nenhuma vez —
 * inclusive o proprio padrao de commit que a sessao usa (`git commit -m
 * "$(cat <<'EOF' ... EOF )"`). Falso positivo e mais grave que buraco: ele
 * trava trabalho legitimo, e a unica saida de quem esbarra nele e desligar o
 * gate inteiro, o que anula a protecao real pelo resto da sessao. Conserto:
 * `removeCorposDeHeredoc()`, chamada ANTES de segmentar — ver comentario da
 * funcao para a forma exata do reconhecimento.
 *
 * RODADA 6, 2026-09-04 (revisor, 3a rodada): FALSO NEGATIVO — o conserto da
 * rodada 5 foi longe demais. `removeCorposDeHeredoc()` passou a descartar o
 * corpo de TODO heredoc, citado ou nao, como se fosse sempre dado literal.
 * Mas em bash so o delimitador CITADO (`<<'EOF'`, `<<"EOF"`, `<<\EOF`) torna
 * o corpo literal de verdade; com delimitador SEM aspas (`<<EOF`) o shell
 * EXPANDE `$(...)` e crase ao montar o heredoc, mesmo que ninguem leia o
 * conteudo depois (`cat > out.txt <<EOF` / `$(git commit --no-verify -m x)`
 * / `EOF` roda o commit de verdade antes mesmo do `cat` escrever nada).
 * Conserto: `removeCorposDeHeredoc()` agora registra se o delimitador de
 * cada marcador estava citado. Citado -> corpo inteiro descartado, como
 * antes (isto e o conserto da rodada 5 e NAO pode regredir). Sem aspas ->
 * o texto ao redor e descartado, mas o CONTEUDO de `$(...)` e de crases
 * dentro do corpo e extraido e devolvido como comando adicional a analisar
 * — mesmo mecanismo de `extraiSubstituicoes()`, so que aplicado ao corpo do
 * heredoc em vez de ao comando bruto.
 *
 * O QUE SABIDAMENTE ESCAPA E NAO SERA PERSEGUIDO (a lista e o valor deste
 * bloco — ser honesto sobre o buraco, nao ser curto):
 *   - indirecao por variavel (`F=--no-verify; git commit $F`) — nao-objetivo
 *     declarado no plano `2026-09-04-nao-mente.md`. O valor de `$F` so existe
 *     depois da expansao do shell, que acontece DEPOIS deste gate ler
 *     `tool_input.command`. Nao ha como cobrir isso lendo o texto do
 *     comando: o gate cobre o que esta ESCRITO nele, nada alem disso;
 *   - qualquer forma de ofuscacao que dependa do SHELL DE VERDADE interpretar
 *     o comando de um jeito que este parser escrito a mao (que nao e um
 *     shell) nao replica com exatidao — `$'...'` com escape ANSI-C, alias,
 *     funcao de shell, `IFS` alterado, encoding, e formas ainda nao medidas.
 *     Este gate cobre os padroes das tres rodadas acima, nao todo padrao
 *     hipotetico;
 *   - deteccao de heredoc (`removeCorposDeHeredoc`) e feita por regex linha a
 *     linha, nao por um parser de shell de verdade: `<<` dentro de uma
 *     string entre aspas so por coincidencia (`echo "ele disse <<EOF>>"`)
 *     pode ser lido como inicio de heredoc por engano; e deslocamento
 *     aritmetico por uma VARIAVEL de um caractere so cujo nome comeca com
 *     letra (`$((v<<n))`) colide com a forma de um delimitador de heredoc —
 *     deslocamento por numero (`$((1<<2))`) NAO colide, porque o delimitador
 *     sem aspas so casa comecando com letra ou `_`. Nenhum dos dois casos
 *     aparece nas formas medidas ate aqui;
 *   - delimitador com escape de barra invertida NO MEIO da palavra (`<<EO\F`)
 *     e citado em bash de verdade (basta UM caractere escapado), mas so
 *     `<<\DELIM` (barra invertida ANTES da palavra inteira) e reconhecido
 *     aqui como citado — `<<EO\F` cai no ramo sem aspas e o casamento do
 *     delimitador de fechamento fica capenga (a variavel `delim` guarda so
 *     `EO`, sem o `F` apos a barra). Nao medido em ataque nenhum ate aqui.
 *
 * ONDE MORA O ENFORCEMENT DE VERDADE, para quem precisar de garantia e nao so
 * de fricção: `pre-receive` no servidor git, ou uma checagem de CI que roda a
 * mesma verificacao e reprova o PR. Nenhum dos dois e alcancado por
 * `--no-verify` por construcao — a flag so desliga hook LOCAL. Este arquivo
 * aqui e o quebra-molas na hora do commit; a garantia final mora nos dois
 * acima, e dizer isso aqui evita que alguem confie demais neste gate.
 *
 * REGRA, tres comandos:
 *   git commit --no-verify | -n | --no-gpg-sign   -> barrado
 *   git push   --no-verify                         -> barrado
 *   qualquer outra chamada de git, inclusive
 *   `git push -n` (que em push e --dry-run, nao --no-verify)  -> passa
 *
 * `-n` so conta para `commit` (onde e sinonimo de `--no-verify`). Em `push`,
 * `-n` e `--dry-run` — bloquear ali barraria uma operacao legitima e nao tem
 * nada a ver com pular verificacao. Isto e invariante do plano (D10).
 *
 * PARSING. `--no-verify` dentro de uma MENSAGEM de commit nao pode disparar o
 * gate (`git commit -m "removi o --no-verify do script"`): o conteudo citado
 * e PRESERVADO como parte do token (nao apagado — apagar e o que deixava a
 * flag citada passar sem barrar, ver historico da tarefa 2 do plano acima),
 * so que o token inteiro (`removi o --no-verify do script`) nunca e igual a
 * `--no-verify`. Aspas adjacentes a texto sem aspas viram UM token so, do
 * jeito que o shell faz (`--no-"verify"` -> `--no-verify`). Fora de aspas
 * simples, barra invertida de escape some e o char seguinte vira literal
 * (`--no\-verify` -> `--no-verify`); dentro de aspas duplas so `\"`, `\\`,
 * `\$` e `` \` `` sao escapes de verdade, e o fechamento da aspa ignora um
 * `\"` escapado (senao um `bash -c "...\"..."` aninhado fecha a aspa cedo
 * demais e quebra a extracao do comando interno).
 * `git -c commit.gpgsign=false commit -m x` tem que continuar identificando
 * `commit` como subcomando (nao a chave `commit.gpgsign=false`) — a mesma
 * varredura de flags-com-valor do `gate-staging-total` resolve isso.
 *
 * Prefixo de opcao longa (o git aceita: `--no-veri` resolve para `--no-verify`
 * se for prefixo unico) conta como a flag inteira — comparado por prefixo
 * contra `--no-verify` e `--no-gpg-sign`, nao por igualdade.
 *
 * Encadeamento (`;`, `|`, `||`, `&&`, `&`, quebra de linha, `(`, `)`) segmenta
 * o comando, e cada segmento e varrido procurando o token `git` em QUALQUER
 * posicao (nao so no inicio) — lista de prefixos aceitos antes do `git`
 * sempre esquece um caso (`then`, `do`, `else`, `{`...). Substituicao de
 * comando `$(...)` e crase tem o delimitador removido e o conteudo interno
 * vira mais um segmento. Linha continuada com `\` + quebra de linha e
 * costurada de volta antes de segmentar, senao a flag fica orfa de comando
 * no segmento seguinte. Parenteses de subshell (`(git commit --no-verify)`)
 * viram separador tambem — tratados DEPOIS da extracao de `$(...)`, entao
 * essa substituicao (que ja funciona) continua intacta.
 *
 * CORPO DE HEREDOC (`<<EOF` ... `EOF`, achado do revisor na rodada 5, ver
 * bloco acima) e removido do comando bruto ANTES de qualquer coisa disto —
 * `removeCorposDeHeredoc()`, chamada no inicio de `segmentosDoComando()`.
 * A LINHA que contem o marcador `<<DELIM` continua no comando depois da
 * limpeza (so o corpo some) — e assim que `git commit -m "$(cat <<'EOF'`
 * continua sendo varrido por `git commit` nessa mesma linha.
 *
 * O tratamento do CORPO depende de o delimitador estar CITADO ou nao
 * (achado do revisor na rodada 6, ver bloco acima — contrapartida exata da
 * rodada 5): com delimitador citado (`<<'EOF'`, `<<"EOF"`, `<<\EOF`) o corpo
 * e DADO de verdade — o bash nao expande nada ali —, e o corpo inteiro e
 * descartado, exatamente como a rodada 5 deixou. Sem aspas (`<<EOF`) o bash
 * EXPANDE `$(...)` e crase ao montar o heredoc antes de qualquer leitura do
 * conteudo — entao o texto ao redor e descartado (continua sem virar
 * separador de segmento, mesmo mecanismo do paragrafo acima), mas o
 * CONTEUDO de cada `$(...)` e de cada crase dentro do corpo e extraido e
 * devolvido por `removeCorposDeHeredoc()` como comando adicional a analisar
 * (mesma extracao de `extraiSubstituicoes()`, aplicada ao corpo em vez de
 * ao comando bruto) — e assim que `$(git commit --no-verify -m x)` dentro
 * de um `<<EOF` sem aspas continua sendo achado, enquanto prosa solta no
 * mesmo corpo (`git commit --no-verify` sem `$(...)` nem crase ao redor)
 * continua sendo ignorada.
 *
 * SHELL AGRUPADO (`bash -c "<cmd>"`, `sh -c '<cmd>'`, com ou sem flags
 * combinadas antes do -c: `bash -lc`, `sh -ec`, `bash -o pipefail -c`).
 * Para `git commit -m`, o conteudo citado e TEXTO (mensagem) e nunca vira
 * comando — e assim que a tarefa anterior fechou o falso positivo de
 * `git commit -m "removi o --no-verify do script"`. Mas para `bash -c`/
 * `sh -c`/`zsh -c`/`dash -c`/`ash -c` (e `busybox sh -c`) — com ou sem
 * caminho e `.exe` na frente do nome (`/bin/bash`, `bash.exe`, achado
 * atacando a terceira rodada) —, o argumento seguinte ao `-c` e uma LINHA DE
 * COMANDO, nao mensagem, e e analisado RECURSIVAMENTE, como se fosse um
 * segmento novo (segmentar, tokenizar, analisaGit, motivoDe de novo). `eval
 * "<comando>"` (achado atacando a terceira rodada tambem) entra na mesma
 * recursao: o argumento de `eval` e uma linha de comando igual a de
 * `bash -c`, so que sem exigir `-c` na frente. A distincao entre linha de
 * comando e mensagem e o proprio token anterior: `-m`/`--message` de `git
 * commit` nunca dispara recursao, so `-c` (ou flag combinada com `c`)
 * precedido do NOME de um shell, ou o token `eval`, disparam. Profundidade
 * tem teto (3): shell dentro de shell dentro de shell alem do teto BARRA em
 * vez de liberar — este gate e fail-closed, e nao ha como provar ausencia de
 * `--no-verify` num aninhamento arbitrario.
 *
 * ESCOPO: vale para todo ator, sem distincao de agente ou janela principal — a
 * trava e sobre o COMANDO, nao sobre quem digita.
 *
 * Saidas de emergencia, as mesmas dos outros gates deste plugin:
 *   - env RAINFOREST_GATE_OFF=1        -> desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo -> desliga naquele repo;
 *   - `.rainforest/config.json` do projeto, chave `gate-git-verificacao`
 *     (registrada em CHAVES de hooks/lib/config.cjs, lida por `ligado()`;
 *     padrao LIGADO — quem quiser desligar declara `false` na chave).
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

// Flags globais do git que consomem o token seguinte (`git -C <dir> commit`).
const FLAG_COM_VALOR = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix",
]);

function git(dir, args) {
  try {
    const s = execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    });
    return s.trim();
  } catch {
    return null;
  }
}

/**
 * Segmenta um trecho de comando em invocacoes independentes. `(` e `)`
 * entram como separador (subshell `(git commit --no-verify)`) — chamado
 * DEPOIS de extraiSubstituicoes(), que ja removeu `$(...)` e crase com
 * delimitador e tudo, entao esta chamada aqui so encontra parenteses de
 * subshell "nu", nunca os de substituicao de comando.
 *
 * CIENTE DE ASPAS: separador (`;`, `|`, `&`, `(`, `)`, `\n`, `||`, `&&`)
 * dentro de `'...'` ou de `"..."` nao separa nada. Maquina de estado:
 *   - dentro de `'...'`, nada e especial, nem barra invertida, nem `"`;
 *   - dentro de `"..."`, barra invertida escapa o char seguinte, e `'` e literal;
 *   - fora de aspas, barra invertida escapa o char seguinte.
 * Se ao final da string ainda estiver dentro de uma aspa aberta (falha de
 * sintaxe no bash de verdade), VOLTA para o split ingenuo (fail-closed).
 * Se o comando contiver flags perigosas e tiver sintaxe invalida (aspa aberta),
 * retorna um segmento que forcara bloqueio.
 */
function segmentos(cmd) {
  const resultado = [];
  let segmento = "";
  let emAspaSimples = false;
  let emAspaDupla = false;
  let emAspaANSIC = false;

  for (let i = 0; i < cmd.length; i++) {
    const char = cmd[i];
    const proximo = cmd[i + 1];
    const anterior = i > 0 ? cmd[i - 1] : "";

    // Dentro de aspas ANSI-C ($'...'): barra invertida escapa o próximo caractere
    if (emAspaANSIC) {
      segmento += char;
      if (char === "\\") {
        // Barra invertida escapa o próximo caractere — assim $\' não fecha a string
        if (proximo !== undefined) {
          segmento += proximo;
          i += 1;
        }
      } else if (char === "'") {
        emAspaANSIC = false;
      }
      continue;
    }

    // Dentro de aspas simples: nada é especial, nem barra, nem aspas duplas
    if (emAspaSimples) {
      segmento += char;
      if (char === "'") {
        emAspaSimples = false;
      }
      continue;
    }

    // Dentro de aspas duplas: barra invertida pode escapar alguns chars
    if (emAspaDupla) {
      segmento += char;
      if (char === "\\") {
        // Barra invertida escapa o próximo caractere
        if (proximo !== undefined) {
          segmento += proximo;
          i += 1;
        }
      } else if (char === '"') {
        emAspaDupla = false;
      }
      continue;
    }

    // Fora de aspas
    if (char === "'" && anterior === "$") {
      // Abertura de string ANSI-C: $'
      emAspaANSIC = true;
      segmento += char;
    } else if (char === "'") {
      emAspaSimples = true;
      segmento += char;
    } else if (char === '"') {
      emAspaDupla = true;
      segmento += char;
    } else if (char === "\\") {
      // Barra invertida escapa o próximo caractere
      segmento += char;
      if (proximo !== undefined) {
        segmento += proximo;
        i += 1;
      }
    } else if (/[\|\n&();]/.test(char) || (char === "|" && proximo === "|") || (char === "&" && proximo === "&")) {
      // Separador encontrado
      if (char === "|" && proximo === "|") {
        if (segmento) resultado.push(segmento);
        segmento = "";
        i += 1;
      } else if (char === "&" && proximo === "&") {
        if (segmento) resultado.push(segmento);
        segmento = "";
        i += 1;
      } else {
        if (segmento) resultado.push(segmento);
        segmento = "";
      }
    } else {
      segmento += char;
    }
  }

  // Se terminou dentro de uma aspa, a sintaxe é ambígua — falha para o lado
  // fechado (fail-closed: bloqueia mais, não menos). Se o comando contém
  // flags perigosas, retorna um marcador especial de ambiguidade; senão, usa
  // split ingênuo. Comando com aspa não fechada é erro de sintaxe no bash
  // de qualquer forma, e o gate não deve premiá-lo com passagem livre.
  if (emAspaSimples || emAspaDupla || emAspaANSIC) {
    const temFlagPerigosa = /--no-verify|--no-gpg-sign|-n(\s|$)/.test(cmd);
    if (temFlagPerigosa) {
      // Marca como ambíguo em vez de fabricar um segmento falso
      return [{ __ambigua: true }];
    }
    return cmd.split(/\|\||&&|[;|\n&()]/);
  }

  if (segmento) resultado.push(segmento);
  return resultado;
}

/**
 * Casa o INICIO de um heredoc (`<<` ou `<<-`, seguido de espacos opcionais e
 * do delimitador em aspas simples, em aspas duplas, com barra invertida na
 * frente da palavra inteira, ou sem aspas nenhuma). NUNCA casa dentro de
 * `<<<` (herestring, ja e nao-objetivo declarado no plano — lookbehind/
 * lookahead barram os dois lados) nem confunde com o operador de
 * deslocamento aritmetico (`$((1<<2))`): o delimitador sem aspas so casa se
 * comecar com letra ou `_`, entao `<<2` (deslocamento por numero) nunca vira
 * heredoc. `<<x` onde `x` e um nome de variavel de um caractere so ainda
 * poderia colidir (ex.: `$((v<<n))`) — caso raro, listado como o que
 * sabidamente escapa no cabecalho do arquivo.
 *
 * Grupos: 1=dash de `<<-`; 2=conteudo entre aspas simples (citado); 3=entre
 * aspas duplas (citado); 4=apos barra invertida da palavra inteira, tipo
 * `<<\EOF` (citado — bash trata delimitador com QUALQUER parte escapada como
 * citado; aqui so a forma "barra antes da palavra inteira" e reconhecida,
 * ver limitacao no cabecalho do arquivo); 5=sem aspas nenhuma (NAO citado —
 * o corpo sofre expansao de `$(...)` e crase, ver `removeCorposDeHeredoc`).
 */
const INICIO_HEREDOC = /(?<!<)<<(-?)(?!<)[ \t]*(?:'([^']*)'|"([^"]*)"|\\([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*))/g;

/**
 * Remove o CORPO de heredocs do comando bruto, ANTES de segmentar. Sem isto,
 * `segmentos()` fatia o corpo por quebra de linha e manda cada linha para
 * `analisaComando` como se fosse codigo — era assim que `cat > docs.md
 * <<EOF` seguido de uma linha citando `--no-verify` em prosa barrava um
 * comando que nao invoca `git` nenhuma vez (achado do revisor, rodada 5,
 * 2026-09-04).
 *
 * A LINHA que contem `<<DELIM` continua no comando depois da limpeza — ela
 * pode ter comando de verdade colado (`git commit -m "$(cat <<'EOF'`, onde
 * `git commit` esta nessa mesma linha). So o CORPO (da linha seguinte ate a
 * linha do delimitador, corpo e linha do delimitador ambos removidos) some
 * da saida principal.
 *
 * O que acontece com o CORPO depende de o delimitador estar CITADO
 * (`'EOF'`, `"EOF"`, `\EOF`) ou nao (`EOF` puro) — achado do revisor,
 * rodada 6, 2026-09-04, contrapartida exata da rodada 5: delimitador citado
 * faz o bash tratar o corpo como literal de verdade (DADO, nunca comando) —
 * o corpo e so descartado, como a rodada 5 deixou. Delimitador SEM aspas
 * sofre expansao de `$(...)` e crase ao ser montado — entao o corpo NAO e
 * so dado: o texto ao redor e descartado, mas o conteudo de cada `$(...)`
 * e de cada crase dentro do corpo e extraido (mesma extracao de
 * `extraiSubstituicoes()`) e devolvido em `extras`, para ser analisado como
 * mais um comando.
 *
 * O corpo vai ate uma linha que contenha SO o delimitador — com `<<-`, tabs
 * no comeco da linha de fechamento sao ignorados na comparacao, do jeito que
 * o bash aceita. Um comando pode ter mais de um heredoc (em linhas
 * diferentes, ou mais de um marcador na mesma linha, ex.: `cmd <<A <<B`) —
 * os corpos sao consumidos na ordem em que os marcadores aparecem.
 *
 * Devolve `{ cmd, extras }`: `cmd` e o comando bruto com todo corpo de
 * heredoc removido (igual ao retorno de antes da rodada 6); `extras` e a
 * lista de comandos extraidos de `$(...)`/crase dentro de corpo NAO citado.
 */
function removeCorposDeHeredoc(cmd) {
  const linhas = cmd.split("\n");
  const saida = [];
  const extras = [];

  let i = 0;
  while (i < linhas.length) {
    const linha = linhas[i];
    saida.push(linha);
    i += 1;

    INICIO_HEREDOC.lastIndex = 0;
    let m;
    const marcadores = [];
    while ((m = INICIO_HEREDOC.exec(linha)) !== null) {
      const delim = m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : m[5];
      const citado = m[2] !== undefined || m[3] !== undefined || m[4] !== undefined;
      if (delim) marcadores.push({ delim, dash: m[1] === "-", citado });
    }

    for (const { delim, dash, citado } of marcadores) {
      const corpo = [];
      while (i < linhas.length) {
        const linhaCorpo = linhas[i];
        i += 1;
        const testado = dash ? linhaCorpo.replace(/^\t+/, "") : linhaCorpo;
        if (testado === delim) break; // linha do delimitador tambem some
        corpo.push(linhaCorpo);
      }
      if (!citado && corpo.length) {
        const [, ...subs] = extraiSubstituicoes(corpo.join("\n"));
        extras.push(...subs);
      }
    }
  }
  return { cmd: saida.join("\n"), extras };
}

/**
 * Costura de volta linha continuada (`\` + quebra de linha): sem isso, a
 * quebra de linha vira separador de segmento e a flag fica orfa de comando
 * no segmento seguinte (`git commit \` + quebra + ` --no-verify -m x`).
 */
function costuraContinuacao(cmd) {
  return cmd.replace(/\\\r?\n/g, " ");
}

/**
 * Extrai o conteudo de `$(...)` (nao aninhado, suficiente para o escopo
 * deste gate) e de `` `...` ``, removendo o delimitador do texto original.
 * Devolve [textoSemSubstituicao, ...conteudoDeCadaSubstituicao] — cada
 * elemento e depois segmentado e analisado como os demais.
 */
function extraiSubstituicoes(cmd) {
  const extras = [];
  let semSub = cmd.replace(/\$\(([^()]*)\)/g, (_, dentro) => { extras.push(dentro); return " "; });
  semSub = semSub.replace(/`([^`]*)`/g, (_, dentro) => { extras.push(dentro); return " "; });
  return [semSub, ...extras];
}

/**
 * Todos os segmentos analisaveis de um comando bruto (ver comentario do
 * topo). Recursiva: cada `extra` que `removeCorposDeHeredoc()` devolve (o
 * conteudo de `$(...)`/crase de dentro de um corpo de heredoc SEM aspas,
 * rodada 6) e um comando por direito proprio, entao passa pelo mesmo
 * tratamento (heredoc -> continuacao -> substituicao -> segmentacao) de
 * novo, e nao so por um `flatMap(segmentos)` direto.
 *
 * Devolve um array de segmentos (strings). Se a leitura de qualquer parte
 * ficou ambígua (aspas não fechadas), marca o array com propriedade
 * `_ambigua: true` — a ambiguidade é sinalizada no array, não num
 * segmento fabricado.
 */
function segmentosDoComando(cmd) {
  const { cmd: semHeredoc, extras } = removeCorposDeHeredoc(cmd);
  const partes = extraiSubstituicoes(costuraContinuacao(semHeredoc));
  const segs = [];
  let ambigua = false;

  for (const parte of partes) {
    const resultSegmentos = segmentos(parte);
    for (const seg of resultSegmentos) {
      // Filtra segmentos marcadores de ambiguidade, marca o array em vez
      if (typeof seg === "object" && seg !== null && seg.__ambigua) {
        ambigua = true;
      } else {
        segs.push(seg);
      }
    }
  }

  for (const extra of extras) {
    const extrasSegs = segmentosDoComando(extra);
    segs.push(...extrasSegs);
    if (extrasSegs._ambigua) ambigua = true;
  }

  if (ambigua) segs._ambigua = true;
  return segs;
}

/**
 * Máquina de estado para percorrer aspas no shell bash, usada tanto por
 * `segmentos()` (para decidir separadores) quanto por `tokens()` (para
 * decidir limite de token). Garante que ambas funções leem a gramática de
 * aspas da mesma forma, evitando divergência.
 *
 * Percorre `texto` e para cada posição marca se está fora de aspas ou dentro
 * de qual tipo: `'...'`, `"..."`, ou `$'...'` (ANSI-C). Devolve array onde:
 *   - 0 = fora de aspas
 *   - 1 = dentro de aspas simples '...'
 *   - 2 = dentro de aspas duplas "..."
 *   - 3 = dentro de aspas ANSI-C $'...'
 *
 * Usado por `segmentos()` e `tokens()` para garantir consistência.
 */
function analisaAspas(texto) {
  const mapa = [];
  let emAspaSimples = false;
  let emAspaDupla = false;
  let emAspaANSIC = false;

  for (let i = 0; i < texto.length; i++) {
    const char = texto[i];
    const proximo = texto[i + 1];
    const anterior = i > 0 ? texto[i - 1] : "";

    // Dentro de aspas ANSI-C ($'...'): barra invertida escapa o próximo caractere
    if (emAspaANSIC) {
      mapa.push(3);
      if (char === "\\") {
        if (proximo !== undefined) {
          i += 1;
          mapa.push(3);
        }
      } else if (char === "'") {
        emAspaANSIC = false;
      }
      continue;
    }

    // Dentro de aspas simples: nada é especial, nem barra, nem aspas duplas
    if (emAspaSimples) {
      mapa.push(1);
      if (char === "'") {
        emAspaSimples = false;
      }
      continue;
    }

    // Dentro de aspas duplas: barra invertida pode escapar alguns chars
    if (emAspaDupla) {
      mapa.push(2);
      if (char === "\\") {
        if (proximo !== undefined) {
          i += 1;
          mapa.push(2);
        }
      } else if (char === '"') {
        emAspaDupla = false;
      }
      continue;
    }

    // Fora de aspas
    mapa.push(0);
    if (char === "'" && anterior === "$") {
      emAspaANSIC = true;
    } else if (char === "'") {
      emAspaSimples = true;
    } else if (char === '"') {
      emAspaDupla = true;
    } else if (char === "\\") {
      if (proximo !== undefined) {
        i += 1;
        mapa.push(0);
      }
    }
  }

  return mapa;
}

/**
 * Tokeniza PRESERVANDO o conteudo citado como parte do token, em vez de
 * apagar (apagar e o que deixava a flag citada passar sem barrar). Aspas
 * adjacentes a texto sem aspas se fundem em UM token so, do jeito que o
 * shell faz: `--no-"verify"` vira o token `--no-verify`; `-m "removi o
 * --no-verify do script"` vira UM token so com a frase inteira (que nunca e
 * igual a `--no-verify`).
 *
 * ESCAPE POR BARRA INVERTIDA (achado atacando a terceira rodada): fora de
 * aspas simples, `\` remove a si mesma e faz o char seguinte virar literal
 * — `--no\-verify` chega ao shell como `--no-verify`, e tem que comparar
 * como tal. Aspas simples preservam a barra invertida literal (shell de
 * verdade nao processa escape dentro delas, e por isso o ramo de `'` abaixo
 * nao trata `\` como especial). Dentro de aspas DUPLAS o fechamento tem que
 * ignorar `\"` escapada (senao um `bash -c "...\"..."` aninhado fecha a
 * aspa cedo demais e quebra a extracao do comando interno) — so `\"`, `\\`,
 * `\$` e `` \` `` sao especiais ali, mesma regra do shell.
 *
 * ASPAS ANSI-C (rodada 7, 2026-09-04): em `$'...'`, a barra invertida
 * escapa o próximo caractere, então `\'` NÃO fecha a aspa. Antes,
 * `segmentos()` entendia escape em ANSI-C mas `tokens()` não, causando
 * divergência. Conserto: replicar a mesma máquina de estado de aspas que
 * `segmentos()` usa, DESCARTANDO as aspas do resultado final (não
 * acumular as aspas no token).
 */
function tokens(seg) {
  const toks = [];
  let cur = "";
  let tem = false;
  let emAspaSimples = false;
  let emAspaDupla = false;
  let emAspaANSIC = false;

  for (let i = 0; i < seg.length; i += 1) {
    const c = seg[i];
    const proximo = seg[i + 1];
    const anterior = i > 0 ? seg[i - 1] : "";

    // Dentro de aspas ANSI-C ($'...'): barra invertida escapa o próximo caractere
    if (emAspaANSIC) {
      if (c === "\\") {
        // Barra invertida escapa o próximo caractere
        if (proximo !== undefined) {
          cur += proximo;
          i += 1;
          tem = true;
        }
      } else if (c === "'") {
        emAspaANSIC = false;
      } else {
        cur += c;
        tem = true;
      }
      continue;
    }

    // Dentro de aspas simples: nada é especial, nem barra, nem aspas duplas
    if (emAspaSimples) {
      if (c === "'") {
        emAspaSimples = false;
      } else {
        cur += c;
        tem = true;
      }
      continue;
    }

    // Dentro de aspas duplas: barra invertida pode escapar alguns chars
    if (emAspaDupla) {
      if (c === "\\") {
        if (proximo !== undefined && '"\\$`'.includes(proximo)) {
          cur += proximo;
          i += 1;
          tem = true;
          continue;
        }
        cur += c;
        tem = true;
      } else if (c === '"') {
        emAspaDupla = false;
      } else {
        cur += c;
        tem = true;
      }
      continue;
    }

    // Fora de aspas
    if (c === "'" && anterior === "$") {
      // Abertura de string ANSI-C: $' — não acumula a aspa
      emAspaANSIC = true;
    } else if (c === "'") {
      // Abertura de aspas simples — não acumula a aspa
      emAspaSimples = true;
    } else if (c === '"') {
      // Abertura de aspas duplas — não acumula a aspa
      emAspaDupla = true;
    } else if (c === "\\" && proximo !== undefined) {
      // Barra invertida fora de aspas escapa o próximo caractere
      cur += proximo;
      i += 1;
      tem = true;
    } else if (/\s/.test(c)) {
      if (tem) { toks.push(cur); cur = ""; tem = false; }
    } else {
      cur += c;
      tem = true;
    }
  }

  if (tem) toks.push(cur);
  return toks;
}

/**
 * null se o segmento nao contem uma chamada de git; senao {sub, args, dirC}.
 * Varre o token `git` em QUALQUER posicao do segmento (nao so no inicio):
 * lista de prefixos aceitos antes dele (`env`, `sudo`, `VAR=valor`...)
 * sempre esquece um caso — `then`, `do`, `else`, `{` inclusive.
 */
function analisaGit(toks) {
  const inicio = toks.findIndex(ehTokenGit);
  if (inicio === -1) return null;
  let i = inicio + 1;

  let dirC = null;
  while (i < toks.length && toks[i].startsWith("-")) {
    if (toks[i] === "-C" && toks[i + 1]) dirC = toks[i + 1];
    i += FLAG_COM_VALOR.has(toks[i]) && !toks[i].includes("=") ? 2 : 1;
  }
  if (i >= toks.length) return null;
  return { sub: toks[i], args: toks.slice(i + 1), dirC };
}

/**
 * true se `token` e uma opcao longa (comeca com `--`) que e PREFIXO de
 * `alvo` — o git aceita prefixo unico de opcao longa (`--no-veri` resolve
 * para `--no-verify`, e o proprio git aceita isso na pratica).
 */
function ehPrefixoDeFlag(token, alvo) {
  return token.length > 2 && token.startsWith("--") && alvo.startsWith(token);
}

/** `-na` contem a curta `n`; `--no-verify` nao e curta e nao conta aqui. */
function temCurta(args, letra) {
  return args.some((t) => /^-[A-Za-z]+$/.test(t) && t.slice(1).includes(letra));
}

/** Motivo do bloqueio, ou null se o segmento e inofensivo. */
function motivoDe(g) {
  if (g.sub === "commit") {
    if (g.args.some((t) => ehPrefixoDeFlag(t, "--no-verify"))) return "git commit --no-verify";
    if (g.args.some((t) => ehPrefixoDeFlag(t, "--no-gpg-sign"))) return "git commit --no-gpg-sign";
    if (temCurta(g.args, "n")) return "git commit -n (equivale a --no-verify)";
    return null;
  }
  if (g.sub === "push") {
    // `-n` em push e --dry-run, nao --no-verify: nao entra aqui de proposito.
    if (g.args.some((t) => ehPrefixoDeFlag(t, "--no-verify"))) return "git push --no-verify";
    return null;
  }
  return null;
}

// Shells cujo `-c <cmd>` recebe uma LINHA DE COMANDO (nao mensagem) como
// argumento seguinte — o argumento e analisado recursivamente.
const NOMES_SHELL = new Set(["bash", "sh", "zsh", "dash", "ash"]);

// Teto de profundidade da recursao em shell -c aninhado. "3 basta": nenhuma
// forma legitima testada precisa de mais, e estourar o teto BARRA (fail
// closed) em vez de liberar, porque nao ha como provar ausencia de
// `--no-verify` num aninhamento arbitrariamente fundo.
const PROFUNDIDADE_MAXIMA = 3;

/**
 * Acha o indice do token de flag `-c` (ou combinada: `-lc`, `-ec`, ...) a
 * partir de `inicio`, pulando flags sem valor pelo caminho e o valor de
 * `-o <opcao>` (forma `bash -o pipefail -c ...`). -1 se nao achar antes de
 * esbarrar num token que nao e flag (o script a rodar, nao `-c`).
 */
function achaFlagC(toks, inicio) {
  for (let j = inicio; j < toks.length; j += 1) {
    const t = toks[j];
    if (t === "-c" || /^-[A-Za-z]*c[A-Za-z]*$/.test(t)) return j;
    if (t === "-o") { j += 1; continue; }
    if (t.startsWith("-")) continue;
    break;
  }
  return -1;
}

/**
 * Nome "puro" de um token de shell: sem caminho (`/bin/bash` -> `bash`,
 * tanto `/` quanto `\` contam, para cobrir caminho Windows) e sem `.exe`
 * (achado atacando a terceira rodada — comparar o token inteiro contra
 * `bash` deixava `/bin/bash -c ...` e `bash.exe -c ...` passarem sem serem
 * reconhecidos como shell).
 *
 * A caixa (maiuscula/minuscula) NAO e normalizada aqui de proposito — quem
 * compara e que decide se normaliza, porque a resposta muda por chamador
 * (ver ehTokenGit e o uso desta funcao em achaInvocacaoShell, achado da
 * rodada 4, revisor independente).
 */
function basenomeShell(tok) {
  const semCaminho = tok.split(/[\\/]/).pop() || tok;
  return semCaminho.replace(/\.exe$/i, "");
}

/**
 * true se `tok` e o executavel `git`, em QUALQUER caixa (`GIT`, `Git`,
 * `gIt`...). Achado da rodada 4 (revisor independente, 2026-09-04): em
 * sistema de arquivos case-insensitive (NTFS no Windows, o padrao do
 * `Git Bash`), o SO resolve `GIT` para o mesmo binario de `git` — a tecla
 * Shift bastava para contornar o gate. Normalizar aqui NAO cria falso
 * positivo: em sistema de arquivos case-SENSITIVE (Linux tipico) o comando
 * `GIT` falharia de qualquer jeito ("command not found"), entao barrar por
 * excesso de zelo nunca acontece de verdade — so em maquina onde `GIT`
 * teria funcionado mesmo.
 *
 * O mesmo raciocinio vale para o nome do shell (`bash`, `BASH`, `/BIN/BASH`)
 * em achaInvocacaoShell, que tambem compara em minusculas — mas NAO para
 * `eval`, que e builtin do shell e e case-sensitive de verdade (`EVAL` da
 * "command not found" no bash), nem para subcomando do git (`commit`,
 * `push`), que o proprio git so reconhece em minusculas (`git COMMIT` ->
 * "'COMMIT' is not a git command"), nem para flags (`--No-Verify` o git
 * rejeita como opcao desconhecida). Normalizar esses tres criaria falso
 * positivo — so o NOME DO EXECUTAVEL resolvido pelo PATH e case-insensitive
 * na pratica.
 */
function ehTokenGit(tok) {
  return tok.toLowerCase() === "git";
}

/**
 * null se os tokens do segmento nao sao uma invocacao `<shell> -c <cmd>`;
 * senao o texto do `<cmd>` (para ser analisado recursivamente). Aceita o
 * nome do shell em qualquer posicao (mesmo motivo do `analisaGit` com
 * `git`: lista de prefixos aceitos antes sempre esquece um caso), com ou
 * sem caminho/`.exe` na frente, e o prefixo `busybox sh -c`.
 */
function achaInvocacaoShell(toks) {
  for (let i = 0; i < toks.length; i += 1) {
    let idx = i;
    if (basenomeShell(toks[idx]).toLowerCase() === "busybox" && NOMES_SHELL.has(basenomeShell(toks[idx + 1] || "").toLowerCase())) idx += 1;
    if (!NOMES_SHELL.has(basenomeShell(toks[idx]).toLowerCase())) continue;
    const j = achaFlagC(toks, idx + 1);
    if (j === -1 || j + 1 >= toks.length) continue;
    return toks[j + 1];
  }
  return null;
}

/**
 * null se os tokens do segmento nao contem `eval`; senao o texto do
 * argumento (para ser analisado recursivamente, mesma recursao do `<shell>
 * -c <cmd>`). `eval "<comando>"` executa o argumento como comando — igual a
 * `bash -c` — e o bash de verdade junta TODOS os argumentos de `eval` com
 * espaco antes de avaliar, entao aqui tambem: comeca no primeiro token que
 * nao e flag (eval nao tem flag de verdade, mas um token comecando com `-`
 * ali e argumento do proprio comando, nao opcao do eval) e junta ate o fim
 * do segmento.
 */
function achaInvocacaoEval(toks) {
  const idx = toks.indexOf("eval");
  if (idx === -1) return null;
  let j = idx + 1;
  while (j < toks.length && toks[j].startsWith("-")) j += 1;
  if (j >= toks.length) return null;
  return toks.slice(j).join(" ");
}

/**
 * Analisa um comando bruto (o `tool_input.command` original, ou o texto de
 * um `-c` de shell aninhado) e devolve {motivo, dirC} do primeiro segmento
 * problematico, ou null se nao achou nada. Recursivo: cada `<shell> -c
 * <cmd>` encontrado tem `<cmd>` analisado de novo, ate `PROFUNDIDADE_MAXIMA`.
 */
function analisaComando(cmd, profundidade) {
  if (profundidade > PROFUNDIDADE_MAXIMA) {
    return { motivo: "shell aninhado alem da profundidade maxima (fail-closed)", dirC: null };
  }
  const segs = segmentosDoComando(cmd);

  // Se a leitura ficou ambígua (aspas não fechadas), bloqueia com motivo honesto
  if (segs._ambigua) {
    return { motivo: `sintaxe ambígua (aspas não fechadas): ${cmd}`, dirC: null };
  }

  for (const seg of segs) {
    const toks = tokens(seg);

    const g = analisaGit(toks);
    if (g) {
      const m = motivoDe(g);
      if (m) return { motivo: m, dirC: g.dirC };
    }

    const cmdAninhado = achaInvocacaoShell(toks);
    if (cmdAninhado !== null) {
      const r = analisaComando(cmdAninhado, profundidade + 1);
      if (r) return r;
    }

    const cmdEval = achaInvocacaoEval(toks);
    if (cmdEval !== null) {
      const r = analisaComando(cmdEval, profundidade + 1);
      if (r) return r;
    }
  }
  return null;
}

function bloqueia(motivo, dir) {
  process.stderr.write(
    `BLOQUEADO pelo gate de verificacao git do rainforest-mind.\n\n` +
    `Comando: ${motivo}\n` +
    `Repo: ${dir}\n\n` +
    `Este gate barra o pulo de verificacao no git — hook de commit ou de push que\n` +
    `existe para pegar erro ANTES de entrar no historico. Pular a verificacao na\n` +
    `hora em que ela reprova e exatamente a hora em que ela importa.\n\n` +
    `Nao use --no-verify, -n (em commit) nem --no-gpg-sign. Se o hook esta\n` +
    `reprovando por motivo legitimo, conserte o motivo — nao pule a checagem.\n\n` +
    `Saidas de emergencia, para quem decide seguir mesmo assim:\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira);\n` +
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo);\n` +
    `  - chave "gate-git-verificacao": false em .rainforest/config.json do\n` +
    `    projeto (desliga so naquele repo, sem precisar de arquivo marcador).\n`
  );
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegivel nunca trava o trabalho do usuario
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  // Toggle do setup, mesmo mecanismo dos outros gates: quem nao quer esta trava
  // num repositorio pode desliga-la por `.rainforest/config.json` do projeto, ou
  // de vez no arquivo de dados. Falha para o lado de LIGAR — config ilegivel nao
  // pode virar trava desligada em silencio.
  try { if (!require("./lib/config.cjs").ligado("gate-git-verificacao", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  if (ev.tool_name !== "Bash") process.exit(0);
  const cmd = (ev.tool_input || {}).command;
  if (typeof cmd !== "string") process.exit(0);

  const achado = analisaComando(cmd, 0);
  if (!achado) process.exit(0);
  const { motivo, dirC } = achado;

  const dir = dirC || cwdDoEvento;
  const toplevel = git(dir, ["rev-parse", "--show-toplevel"]) || dir;
  if (fs.existsSync(path.join(toplevel, ".rainforest-gate-off"))) process.exit(0);

  bloqueia(motivo, dir);
}

main();
