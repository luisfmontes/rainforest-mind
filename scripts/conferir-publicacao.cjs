#!/usr/bin/env node
/**
 * Confere um relatório ANTES de ele sair da máquina — e RECUSA, em vez de avisar.
 *
 * POR QUE EXISTE, com data. O `commands/feedback.md` mandava, desde sempre:
 * "se o achado citar credencial, dado de cliente ou fonte de cliente, anonimize
 * antes de gravar". A regra estava escrita, era clara, e mesmo assim, em
 * 2026-08-10, um relatório foi gravado e commitado contendo:
 *
 *   - o telefone de um terceiro, em JID de WhatsApp (`5547...@s.whatsapp.net`);
 *   - o nome completo dessa pessoa;
 *   - o caminho do repositório do cliente, o parâmetro e a tela do sistema.
 *
 * Ficou no repositório por um dia, e só saiu porque o repo ia ser publicado e
 * alguém foi procurar. É a lição mais repetida deste acervo, aplicada a ele
 * mesmo: **regra escrita não alcança o modo de falha em que quem a leu erra
 * mesmo assim.** O que alcança é código com exit code.
 *
 * E o custo do vazamento MUDOU: enquanto o relatório era markdown num repo
 * privado, um deslize dava para corrigir antes de alguém ver. Agora o
 * `/feedback` abre Issue — que é público no instante em que é criado, e que
 * fica no índice de busca mesmo depois de editado. Não há "corrigir antes".
 *
 * O QUE ELE NÃO FAZ, e é importante dizer: ele não detecta NOME DE PESSOA. Não
 * há padrão para isso. Ele detecta o que tem forma — telefone, e-mail, JID,
 * caminho de home, credencial. O nome do Emerson naquele relatório teria
 * passado por aqui; o telefone dele, não. Por isso a saída limpa não diz "está
 * seguro", diz "não achei o que sei procurar", e lembra do resto.
 *
 * Uso:
 *   node scripts/conferir-publicacao.cjs <arquivo>     # exit 2 se achar algo
 *   cat rascunho.md | node scripts/conferir-publicacao.cjs -
 *   node scripts/conferir-publicacao.cjs <arquivo> --json
 *
 * MODO --commit (D10, 2026-09-12): o que se publica é o COMMIT, não o disco.
 * Edição não commitada anuncia release que não existe, e segredo limpo no
 * disco mas presente no commit vai para o público do mesmo jeito — o passo de
 * release do plugin de terceiro que inspirou isto lê `git show <sha>:<path>`, nunca
 * o worktree, por este motivo.
 *
 *   node scripts/conferir-publicacao.cjs --commit             # HEAD
 *   node scripts/conferir-publicacao.cjs --commit <rev>
 *   node scripts/conferir-publicacao.cjs --commit <a>..<b>     # range de dois commits
 *   node scripts/conferir-publicacao.cjs --commit HEAD --json
 *
 * Varre os arquivos rastreados tocados (um commit: `git show --name-only
 * --format= <rev>`; range: `git diff --name-only <a> <b>`), lê cada um do
 * COMMIT (`git show <rev-ou-b>:<path>`, nunca do disco) e roda `conferir()`
 * igual ao modo de arquivo. Além disso: (1) compara o conteúdo do commit com o
 * do disco — se divergirem, achado `diverge-do-commit`, porque edição não
 * commitada não vai para o público mas o relatório mentiria se dissesse que o
 * commit está limpo por causa dela; (2) chama
 * `scripts/conferir-duplicacao.cjs --raiz <toplevel> --json` e propaga achado
 * `duplicata` por grupo. Exit 2 se algum achado, 0 se nenhum. O modo antigo
 * (`<arquivo>` ou `-`) não muda em nada — os dois modos coexistem.
 *
 * Ambiente (git ausente, rev/range inexistente): exit 69 (EX_UNAVAILABLE,
 * convenção D5 — ver `scripts/conferir-entrega.cjs`), stderr começando com
 * `nao-verificavel: <motivo>`. Não é reprovação, é falta de condição para medir.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

/**
 * Uma referência de variável no COMEÇO do valor, nas quatro formas que
 * aparecem em config e workflow: interpolação de shell com e sem chaves,
 * variável do Windows, e expressão do GitHub Actions — inclusive cortada no
 * primeiro espaço, que é como a regex de credencial a captura.
 *
 * A ordem das alternativas importa: a expressão do Actions é reconhecida
 * antes da interpolação simples, senão a chave dupla casaria como chave
 * única e o resto entraria como literal grudado.
 */
const REFERENCIA_DE_VARIAVEL = new RegExp(
  [
    '^(?:',
    '\\$\\{\\{[^}]*\\}\\}',   // ${{ secrets.X }}
    '|\\$\\{\\{',              // "${{" — cortada no espaço (Issue #173)
    '|\\$\\{[^}]*\\}',        // ${VAR} e ${VAR:-padrao}
    '|\\$[A-Za-z_]\\w*',       // $VAR
    '|%[^%\\s]+%',           // %VAR%
    ')',
  ].join('')
);

/**
 * Prefixo de identificador de plataforma (GitHub Actions run, job, comment, PR, commit, discussion).
 * Ancorada no FIM do trecho anterior ao match, casando exatamente um destes:
 * - runs/ (Actions run id, 11 dígitos)
 * - jobs/ (Actions job id, 13 dígitos)
 * - issuecomment- (PR/Issue comment id, 10 dígitos)
 * - pull/ (PR id, qualquer tamanho)
 * - issues/ (Issue id, qualquer tamanho)
 * - commit/ (commit sha, 40 hex)
 * - discussion_r (discussion reply id, qualquer tamanho)
 *
 * D27: id de run do Actions (11 dígitos) e de comentário de PR (10 dígitos)
 * casam a forma de telefone e nenhuma das três isenções (dígito repetido, hex,
 * dump hexadecimal) os alcança; a mensagem manda "confirmar que é ID" e não
 * existe como confirmar sem desligar o gate inteiro. A isenção por contexto
 * tem a mesma forma da isenção de hex (que já olha ±5 caracteres), não cria
 * ritual e não mexe na faixa de dígitos.
 */
const PREFIXO_DE_ID_DE_PLATAFORMA = /(?:runs\/|jobs\/|issuecomment-|pull\/|issues\/|commit\/|discussion_r)$/;

/**
 * Cada padrão diz o que é e por que dói — mensagem de trava que só nomeia o
 * regex manda quem foi barrado adivinhar o conserto.
 *
 * `exemplo` é o que aparece na saída no lugar do trecho real: mostrar o dado
 * vazado na tela de quem está tentando não vazá-lo seria irônico e inútil.
 */
const PADROES = [
  {
    id: 'jid-whatsapp',
    // A faixa foi `\d{10,15}` até 2026-09-02, e parava CURTA: cobria JID de
    // conversa direta (o telefone, 12–13 dígitos) e deixava passar JID de
    // GRUPO, que tem 18. Issue #149, e o custo foi medido — o `vigias/ERROS.md`
    // da `main` carregou o JID real do grupo das rondas por dias.
    //
    // O modo de falha é o da regra 12, e é o pior tipo: o instrumento
    // RESPONDEU. O JID de grupo acendia o padrão genérico `telefone`, marcado
    // `(pode ser falso positivo)` — que é justamente a categoria que se aprende
    // a ignorar —, em vez desta regra, que é a que traz a instrução certa. Saída
    // plausível, medindo outra coisa.
    re: /\b(\d{10,20})@(s\.whatsapp\.net|g\.us)\b/g,
    o_que: 'JID de WhatsApp — contém o telefone completo, com DDI e DDD',
    faca: 'troque por um marcador (`<jid-do-contato>`); o ID da mensagem sozinho já basta para investigar',
    // Dígito repetido não é dado de ninguém: `000000000000000000@g.us` é o
    // placeholder de `vigias/vigia.config.exemplo.json`, arquivo versionado que
    // documenta o FORMATO. Sem esta isenção, alargar a faixa faria o gate
    // recusar a própria documentação — certo na forma, errado no mérito, que é
    // como uma trava vira `--forcar` no dedo de quem usa.
    //
    // A isenção é por dígito repetido, não por lista de placeholders conhecidos:
    // um JID em que todos os dígitos são iguais não carrega telefone nenhum, e
    // isso vale para o placeholder que ainda não foi escrito.
    so_se: (m) => !/^(\d)\1*$/.test(m[1]),
  },
  {
    id: 'telefone',
    re: /(?:\+\d{1,3}[\s-]?)?\(?\d{2}\)?[\s-]?9?\d{4}[\s-]?\d{4}\b/g,
    o_que: 'sequência com forma de telefone',
    faca: 'remova, ou confirme que é ID/timestamp e não telefone',
    // Timestamp de 13 dígitos e hash numérico batem aqui. Falso positivo custa
    // uma olhada; falso negativo custa o telefone de alguém num Issue público.
    pode_ser_falso: true,
    // Mesma isenção da regra de JID, e pelo mesmo motivo: sequência de dígito
    // repetido não é telefone de ninguém. Sem ela, o placeholder de
    // `vigias/vigia.config.exemplo.json` fazia o gate recusar um arquivo
    // versionado do próprio repositório — em toda rodada, desde sempre. Falso
    // positivo permanente em arquivo que nunca vai mudar é como se aprende a
    // ignorar a saída inteira.
    so_se: (m, linha) => {
      // Issue #144: saída de xxd / hexdump -C / od -tx1 tem forma mecânica, e o
      // gate lia bytes como telefone — barrando a única evidência que prova um
      // defeito de encoding. A isenção vale só para match DENTRO dos grupos hex;
      // a coluna ASCII do dump, se mostrar um telefone legível, continua recusada.
      if (dentroDeDumpHex(m, linha)) return false;

      // D27: GitHub Actions run, job, PR, Issue, commit, discussion — IDs de
      // plataforma que casam forma de telefone mas não são telefone de ninguém.
      // A isenção olha o prefixo imediatamente antes do match: se termina com
      // `runs/`, `jobs/`, `issuecomment-`, `pull/`, `issues/`, `commit/`,
      // ou `discussion_r`, é ID de plataforma, não telefone.
      // O match de telefone pode começar no meio de sequência numérica contínua.
      // Procura para trás até o primeiro dígito da sequência.
      let primeiroDigito = m.index;
      while (primeiroDigito > 0 && /\d/.test(linha[primeiroDigito - 1])) {
        primeiroDigito--;
      }
      const antes = linha.substring(0, primeiroDigito);
      if (PREFIXO_DE_ID_DE_PLATAFORMA.test(antes)) return false;

      // SHA-1 e outras sequências de hex (7-40 caracteres) podem conter
      // subsequências que parecem telefone. Isenta matches DENTRO de um token hex.
      const inicio = Math.max(0, m.index - 5);
      const fim = Math.min(linha.length, m.index + m[0].length + 5);
      const contexto = linha.substring(inicio, fim);
      // O token hex precisa ter LETRA de hex. Sem essa exigência a classe
      // de caracteres casa uma corrida de dígitos puros, e todo telefone sem
      // máscara com 7+ dígitos virava "hash" e saía isento — medido em
      // 2026-09-04, uma linha com onze dígitos crus devolvia achado nenhum,
      // que é exatamente o falso negativo que esta regra existe para não
      // ter. Hash de 40 posições sem nenhum a-f é possível na teoria e custa
      // uma olhada; telefone que passa custa o telefone de alguém.
      const tokenHex = /[0-9a-fA-F]{7,40}/.exec(contexto);
      if (tokenHex && /[a-fA-F]/.test(tokenHex[0])) {
        const localNoContexto = m.index - inicio;
        if (localNoContexto >= tokenHex.index && localNoContexto < tokenHex.index + tokenHex[0].length) {
          return false; // dentro de token hex, isenta
        }
      }

      const digitos = m[0].replace(/\D/g, '');
      return !/^(\d)\1*$/.test(digitos);
    },
  },
  {
    id: 'email',
    re: /\b[\w.+-]+@(?!s\.whatsapp\.net|g\.us)[\w-]+\.[\w.]{2,}\b/g,
    o_que: 'endereço de e-mail',
    faca: 'troque por `<email>` — endereço de terceiro em Issue público vira alvo de spam',
  },
  {
    id: 'caminho-de-home',
    // O segmento do usuário sai em grupo de captura para o `so_se` poder olhá-lo.
    re: /[A-Za-z]:\\Users\\([^\\\s"'`]+)|\/(?:home|Users)\/([^/\s"'`]+)/g,
    o_que: 'caminho de pasta pessoal — carrega o nome de usuário da máquina',
    faca: 'use `<home>` ou um caminho relativo; o caminho absoluto raramente é o que prova o defeito',
    // PLACEHOLDER NÃO É NOME DE NINGUÉM — a terceira regra desta lista a ganhar
    // esta isenção, e pelo mesmo motivo das duas primeiras (Issue #149): a regra
    // recusava a própria documentação do formato que ela ensina. O `faca` acima
    // manda "use `<home>`", e o texto que obedecia era recusado igual.
    //
    // Medido em 2026-09-02: a varredura da árvore antes de tornar o repositório
    // público devolveu 32 arquivos recusados, e `caminho-de-home` respondia por
    // 17 deles — a maioria placeholder ou código que MANIPULA caminho de home.
    // Gate que grita em 17 arquivos que nunca vão mudar ensina a ignorar a saída
    // inteira, e é assim que ele deixa de pegar o 18º, que é real.
    //
    // A isenção é por FORMA, não por lista: `<qualquer coisa>`, `%VAR%` e
    // `$VAR` nunca são nome de usuário em disco. Nome novo de placeholder que
    // alguém invente amanhã já entra isento.
    so_se: (m) => {
      const nome = m[1] || m[2] || '';
      const ehPlaceholder = /^<.*>$/.test(nome)
        || /^%.*%$/.test(nome)
        || nome.startsWith('$');
      return !ehPlaceholder;
    },
  },
  {
    id: 'credencial',
    re: /\b(senha|password|api[_-]?key|apikey|secret|token|authorization)\s*[:=]\s*["']?(\S+)/gi,
    o_que: 'credencial atribuída a uma chave',
    faca: 'nunca cole credencial em relatório, nem revogada — troque por `<redigido>`',
    // O `i` vale para a CHAVE, e não é negociável: `API_KEY` e `SENHA` seguidas de dois-pontos são as
    // formas mais comuns em log e config, e padrão case-sensitive fica cego para
    // as duas. Quem separa prosa de segredo é o `so_se`, em código — a distinção
    // não cabe na mesma regex que ignora caixa.
    //
    // 2026-08-17: a palavra `token` seguida de dois-pontos e prosa comum ("Regua
    // de orcamento de token: medir a abertura antes de comprimir...") recusou um
    // relatório legítimo e obrigou a truncar a evidência que ele existia para
    // mostrar. A liberação é estreita de propósito: valor de palavra curta, toda
    // minúscula, E a linha seguindo com mais palavras. Dúvida captura — valor
    // sozinho na linha continua recusado, mesmo minúsculo.
    //
    // Referência de variável não é segredo — a senha está num lugar seguro,
    // não no arquivo. Isenta interpolação de shell (${VAR}, $VAR), variáveis
    // do Windows (%VAR%), e expressões do GitHub Actions (${{ secrets.X }}).
    so_se: (m, linha) => {
      const valor = m[2].replace(/^["']+/, '');

      // Isenta referências de variável (não são segredos colados). A isenção é
      // pelo COMEÇO do valor, não pelo valor inteiro — e essa diferença é o
      // caso real da Issue #173. Numa URL de clone autenticado do Actions, o
      // valor capturado vai até o próximo espaço e leva o host junto (a
      // interpolação, o arroba e o repositório, tudo num token só); e na forma
      // de expressão do Actions ele para nas duas chaves de abertura, porque a
      // captura da regex é `\S+`. Ancorar no valor inteiro deixava as duas
      // formas acusadas, que é o estado que a Issue reporta.
      // ... mas a isenção cobre o que a REFERÊNCIA cobre, e nada além.
      // Ancorada só no começo, ela isentava o valor inteiro por causa do
      // prefixo: medido em 2026-09-04, uma chave de senha apontando para uma
      // variável com um literal emendado logo depois do fecha-chaves saía
      // limpa — indireção usada como disfarce. Quem decide é o que vem DEPOIS
      // da referência. Delimitador de URL ou de caminho é estrutura, e é a
      // forma real da Issue #173 (a variável, o arroba e o repositório num
      // token só). Caractere de palavra grudado no fecha-chaves é literal
      // concatenado, e literal concatenado numa chave de credencial é segredo
      // colado.
      const ref = REFERENCIA_DE_VARIAVEL.exec(valor);
      if (ref) {
        const resto = valor.slice(ref[0].length);
        // O recuo de `${VAR:-padrao}` NAO e olhado, e essa decisao custou uma
        // rodada de revisao. A versao anterior tratava todo padrao como
        // literal colado, e o efeito medido em 2026-09-05 foi recusar as duas
        // formas mais comuns de `docker-compose.yml` e `.env.example`, em que
        // o padrao e justamente um placeholder ("changeme", "postgres").
        // Trava que grita no arquivo mais comum do mundo e como se ensina
        // alguem a rodar com a saida de emergencia ligada — e ai ela nao pega
        // mais o caso real. O que segura segredo escondido num recuo e a
        // regra `chave-conhecida`, que olha o texto inteiro e independe desta
        // isencao; segredo SEM prefixo conhecido num recuo e a fresta que
        // fica, registrada em "Em aberto" no design.
        if (!/^[A-Za-z0-9_]/.test(resto)) return false;
      }

      const prosaCurta = /^[a-zà-ú]{1,12}$/.test(valor);
      const depois = linha.slice(m.index + m[0].length).trim().split(/\s+/).filter(Boolean);
      return !(prosaCurta && depois.length >= 2);
    },
  },
  {
    id: 'chave-conhecida',
    re: /\b(gh[pousr]_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{10,})\b/g,
    o_que: 'chave com prefixo conhecido (GitHub, OpenAI, Slack)',
    faca: 'REVOGUE a chave antes de qualquer outra coisa, e só depois edite o texto',
  },
];

/**
 * Termos que não têm FORMA — nome de empregador, de cliente, de projeto interno,
 * de fonte de trabalho. Nenhum regex os descobre; só uma lista os reconhece.
 *
 * POR QUE A LISTA NÃO MORA AQUI, e é a decisão inteira deste bloco: escrever os
 * termos num arquivo versionado deste repositório **é** o vazamento que a trava
 * existe para impedir. A lista mora em `~/.rainforest/termos-proibidos.txt`,
 * fora da árvore, um termo por linha, `#` comenta. O repositório público carrega
 * o MECANISMO; a máquina de quem tem os termos carrega os termos.
 *
 * Custo disso, dito de frente: em máquina sem o arquivo a trava não sabe nada
 * sobre termo nenhum — e é por isso que a ausência sai na tela junto com o
 * verde, no `CEGO`, em vez de passar calada. Verde silencioso sem a lista seria
 * a mesma falha do relatório de 2026-08-10: o instrumento respondendo "não achei"
 * quando na verdade não procurou.
 *
 * Nasceu em 2026-09-08, depois de uma varredura achar 30 arquivos rastreados
 * carregando nome de empregador, de cliente e de projeto interno num repositório
 * público desde 02/09.
 */
function carregarTermosPrivados() {
  const base = process.env.HOME || process.env.USERPROFILE || '';
  if (!base) return { caminho: null, termos: [] };
  const caminho = `${base}/.rainforest/termos-proibidos.txt`;
  let bruto;
  try {
    bruto = fs.readFileSync(caminho, 'utf8');
  } catch {
    return { caminho: null, termos: [] };
  }
  const termos = bruto
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
  return { caminho: termos.length ? caminho : null, termos };
}

const TERMOS_PRIVADOS = carregarTermosPrivados();

if (TERMOS_PRIVADOS.termos.length) {
  // Sem `\b`: termo com hífen, barra ou ponto (`acme-servicos`, `squad/plugins`)
  // não tem fronteira de palavra nas pontas, e exigir uma deixaria passar
  // justamente os compostos. Substring casa demais de vez em quando — falso
  // positivo custa uma olhada, falso negativo custa o termo publicado.
  //
  // Os exemplos deste comentário são SINTÉTICOS de propósito, e a primeira
  // versão não era: ela citava dois termos reais da lista, e a própria trava os
  // pegou na varredura de estreia. Exemplo em comentário é texto publicado como
  // qualquer outro — quem documenta a trava é a primeira pessoa a tropeçar nela.
  const alternativa = TERMOS_PRIVADOS.termos
    .map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .sort((a, b) => b.length - a.length) // o mais longo primeiro: `acme-servicos` antes de `acme`
    .join('|');
  PADROES.push({
    id: 'termo-privado',
    re: new RegExp(`(?:${alternativa})`, 'gi'),
    // A mensagem NUNCA nomeia o termo que bateu — o achado sai por linha e por
    // id, e o script inteiro já é assim (nenhum padrão ecoa o trecho casado).
    // Nomear o termo aqui o imprimiria em log de CI, que é público.
    o_que: 'termo da sua lista privada — nome de empregador, cliente, projeto ou fonte de trabalho',
    faca: 'troque por um equivalente sintético e consistente; a lista está em ~/.rainforest/termos-proibidos.txt',
  });
}

/** O que o script sabe que NÃO sabe. Sai junto com o verde, de propósito. */
const CEGO = [
  'nome de pessoa — não há padrão para isso, e foi exatamente o que passou em 2026-08-10',
  ...(TERMOS_PRIVADOS.termos.length
    ? [`nome de cliente/projeto FORA da sua lista privada (${TERMOS_PRIVADOS.termos.length} termo(s) carregado(s))`]
    : ['nome de cliente, de sistema ou de projeto interno — e a lista privada NAO foi carregada: crie ~/.rainforest/termos-proibidos.txt, um termo por linha']),
  'print, log ou stack trace colado com conteúdo de terceiro dentro',
];

// Trecho hex de um dump: offset opcional (7–8 hex, dois-pontos opcional) seguido
// de pelo menos quatro grupos de 2 ou 4 hex separados por espaço. É a forma de
// `xxd`, `hexdump -C` e `od -An -tx1`; prosa com números não a produz.
const RE_TRECHO_HEX = /^\s*(?:[0-9a-f]{7,8}:?\s+)?(?:[0-9a-f]{2}(?:[0-9a-f]{2})?\s+){3,}[0-9a-f]{2}(?:[0-9a-f]{2})?/i;
function dentroDeDumpHex(m, linha) {
  const t = RE_TRECHO_HEX.exec(linha);
  return !!t && m.index + m[0].length <= t[0].length;
}

function conferir(texto) {
  const achados = [];
  for (const p of PADROES) {
    const linhas = texto.split('\n');
    linhas.forEach((linha, i) => {
      p.re.lastIndex = 0;
      let bateu;
      if (p.so_se) {
        // Padrão com `so_se` decide olhando o match inteiro e a linha, então aqui
        // é `exec` e não `test`: um único match liberado não pode liberar a linha,
        // e um único match capturado já a recusa.
        bateu = false;
        let m;
        while ((m = p.re.exec(linha)) !== null) {
          if (p.so_se(m, linha)) { bateu = true; break; }
          if (m.index === p.re.lastIndex) p.re.lastIndex += 1;
        }
      } else {
        bateu = p.re.test(linha);
      }
      if (bateu) {
        achados.push({ id: p.id, linha: i + 1, o_que: p.o_que, faca: p.faca, pode_ser_falso: !!p.pode_ser_falso });
      }
    });
  }
  return achados;
}

/**
 * Roda `git` sem depender de `-C`: o cwd do processo já É o repositório que
 * se quer conferir, e `git -C <dir>` fora de um repositório sobe para o pai
 * em SILÊNCIO (a mesma armadilha documentada em `conferir-entrega.cjs`) — com
 * `cwd:` no spawn, "não é repositório git" falha alto, nunca finge sucesso
 * no lugar errado.
 */
function runGit(args) {
  let r;
  try {
    r = spawnSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  } catch (e) {
    return { status: 127, stdout: '', stderr: 'git nao encontrado no PATH' };
  }
  if (!r || (r.error && r.error.code === 'ENOENT')) {
    return { status: 127, stdout: '', stderr: 'git nao encontrado no PATH' };
  }
  if (r.error) {
    return { status: 127, stdout: '', stderr: String(r.error.message || r.error) };
  }
  return { status: r.status === null ? 127 : r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

function primeiraLinha(s) {
  return String(s || '').trim().split(/\r?\n/)[0] || '';
}

/** Modo `--commit`: confere o que o COMMIT carrega, não o disco (D10). */
function modoCommit(spec, json) {
  const top = runGit(['rev-parse', '--show-toplevel']);
  if (top.status !== 0) {
    const motivo = top.status === 127
      ? 'git nao encontrado no PATH'
      : 'diretorio atual nao e repositorio git';
    process.stderr.write(`nao-verificavel: ${motivo}\n`);
    return 69;
  }
  const toplevel = top.stdout.trim();

  const ehRange = spec.includes('..');
  let arquivos;
  let revLeitura;
  if (ehRange) {
    const idx = spec.indexOf('..');
    const a = spec.slice(0, idx);
    const b = spec.slice(idx + 2) || 'HEAD';
    const diff = runGit(['diff', '--name-only', a, b]);
    if (diff.status !== 0) {
      process.stderr.write(`nao-verificavel: range invalido '${spec}': ${primeiraLinha(diff.stderr)}\n`);
      return 69;
    }
    arquivos = diff.stdout.split('\n').map((s) => s.trim()).filter(Boolean);
    revLeitura = b;
  } else {
    // diff-tree, nao `git show --name-only`: para um MERGE commit o `show` sem
    // -m lista ZERO arquivos e o modo saia "CONFERIDO" sem ler nada (achado da
    // revisao de 2026-09-12). `-m --first-parent` compara com o primeiro pai
    // (o que o merge trouxe para a branch); `--root` cobre o commit inicial.
    const show = runGit(['diff-tree', '--root', '-r', '-m', '--first-parent', '--no-commit-id', '--name-only', spec]);
    if (show.status !== 0) {
      process.stderr.write(`nao-verificavel: rev invalida '${spec}': ${primeiraLinha(show.stderr)}\n`);
      return 69;
    }
    arquivos = show.stdout.split('\n').map((s) => s.trim()).filter(Boolean);
    revLeitura = spec;
  }

  const achados = [];
  for (const relPath of arquivos) {
    const cat = runGit(['show', `${revLeitura}:${relPath}`]);
    if (cat.status !== 0) continue; // arquivo removido/ilegivel naquela rev: fora do escopo
    const conteudoCommit = cat.stdout;

    for (const a of conferir(conteudoCommit)) achados.push({ ...a, arquivo: relPath });

    let conteudoDisco = null;
    try {
      conteudoDisco = fs.readFileSync(path.join(toplevel, relPath), 'utf8');
    } catch {
      // sem arquivo no disco tambem e divergencia: o commit anuncia algo que
      // nao existe mais para ser conferido de novo antes de publicar.
    }
    if (conteudoDisco !== conteudoCommit) {
      achados.push({
        id: 'diverge-do-commit',
        arquivo: relPath,
        linha: null,
        o_que: 'arquivo em disco difere do commit que vai ser publicado',
        faca: 'commite ou descarte antes de publicar',
        pode_ser_falso: false,
      });
    }
  }

  const dup = spawnSync(
    process.execPath,
    [path.join(__dirname, 'conferir-duplicacao.cjs'), '--raiz', toplevel, '--json'],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }
  );
  if (dup.status === 2) {
    try {
      const dados = JSON.parse(dup.stdout);
      for (const grupo of dados.duplicados || []) {
        achados.push({
          id: 'duplicata',
          arquivo: grupo.join(' == '),
          linha: null,
          o_que: `arquivos identicos byte a byte: ${grupo.join(', ')}`,
          faca: 'reconcilie os arquivos ou remova a copia antes de publicar',
          pode_ser_falso: false,
        });
      }
    } catch {
      // saida do conferir-duplicacao nao veio em JSON valido: nao inventa achado.
    }
  }

  if (json) {
    console.log(JSON.stringify({ modo: 'commit', spec, achados, cego: CEGO }, null, 2));
    return achados.length ? 2 : 0;
  }

  if (!achados.length) {
    console.log('CONFERIDO — nao achei nada com forma de dado sensivel no commit.');
    console.log('');
    console.log('Isto NAO quer dizer "esta seguro". Quer dizer "nao achei o que sei');
    console.log('procurar". Continua com voce:');
    for (const c of CEGO) console.log(`  - ${c}`);
    return 0;
  }

  console.log(`RECUSADO — ${achados.length} achado(s) no commit.\n`);
  for (const a of achados) {
    const onde = a.linha != null ? `${a.arquivo}:${a.linha}` : a.arquivo;
    console.log(`  ${onde}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}`);
    console.log(`    ${a.o_que}`);
    console.log(`    -> ${a.faca}`);
  }
  console.log('');
  console.log('Corrija e rode de novo. E lembre do que este script NAO ve:');
  for (const c of CEGO) console.log(`  - ${c}`);
  return 2;
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');

  const idxCommit = args.indexOf('--commit');
  if (idxCommit !== -1) {
    let valor = args[idxCommit + 1];
    if (!valor || valor.startsWith('--')) valor = 'HEAD';
    process.exit(modoCommit(valor, json));
    return;
  }

  const alvo = args.find((a) => !a.startsWith('--'));
  if (!alvo) {
    console.error('uso: node scripts/conferir-publicacao.cjs <arquivo>|- [--json]');
    console.error('     node scripts/conferir-publicacao.cjs --commit [<rev>|<a>..<b>] [--json]');
    process.exit(1);
  }

  let texto;
  try {
    texto = alvo === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(alvo, 'utf8');
  } catch (e) {
    console.error(`erro: nao consegui ler ${alvo}`);
    process.exit(1);
  }

  const achados = conferir(texto);

  if (json) {
    console.log(JSON.stringify({ arquivo: alvo, achados, cego: CEGO }, null, 2));
    process.exit(achados.length ? 2 : 0);
  }

  if (!achados.length) {
    console.log('CONFERIDO — nao achei nada com forma de dado sensivel.');
    console.log('');
    console.log('Isto NAO quer dizer "esta seguro". Quer dizer "nao achei o que sei');
    console.log('procurar". Continua com voce:');
    for (const c of CEGO) console.log(`  - ${c}`);
    process.exit(0);
  }

  console.log(`RECUSADO — ${achados.length} trecho(s) com forma de dado sensivel.\n`);
  for (const a of achados) {
    console.log(`  linha ${a.linha}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}`);
    console.log(`    ${a.o_que}`);
    console.log(`    -> ${a.faca}`);
  }
  console.log('');
  console.log('Corrija e rode de novo. E lembre do que este script NAO ve:');
  for (const c of CEGO) console.log(`  - ${c}`);
  process.exit(2);
}

if (require.main === module) main();
module.exports = { conferir, PADROES, CEGO, TERMOS_PRIVADOS, carregarTermosPrivados };
