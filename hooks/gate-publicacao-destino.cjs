#!/usr/bin/env node
/**
 * PreToolUse — barra escrita de dados sensíveis em arquivo rastreado.
 *
 * Incidente da Issue #83 (2026-08-08): um `progress.jsonl` versionado em repo
 * público recebeu um JID de WhatsApp colado como evidência de smoke. Ficou
 * 16 dias exposto. Conserto exigiu filter-branch em 211 commits e **mesmo assim
 * não bastou**, porque em rede de fork o objeto continua servido por SHA.
 *
 * O script `scripts/conferir-publicacao.cjs` já detecta o que tem forma
 * (telefone, JID, email, caminho de home, credencial). Exit 2 = recusado.
 * O buraco **não é alcance, é chamada**: nenhum artefato de fluxo passa por ali,
 * só markdown de instrução.
 *
 * **P2 vira hook, não vira parágrafo**: um parágrafo a mais seria exatamente a
 * coisa que já falhou. Regra escrita não alcança o modo de falha em que quem a
 * leu erra mesmo assim. O que alcança é código com exit code.
 *
 * ESCOPO, deliberadamente estreito:
 *   - Write/Edit/MultiEdit (ferramentas de escrita)
 *   - arquivo dentro de repo git — fora de repo, passa
 *   - arquivo NÃO gitignorado — se está ignorado, passa (nunca vira histórico)
 *   - conteúdo sendo escrito (tool_input.content para Write, tool_input.new_string
 *     para Edit)
 *   - roda `conferir-publicacao.cjs` sobre o conteúdo novo
 *   - se achar dados sensíveis, bloqueia com mensagem útil que nomeia o padrão
 *
 * Saídas de emergência, as mesmas dos outros gates:
 *   - env RAINFOREST_GATE_OFF=1  → desliga na sessão inteira
 *   - arquivo .rainforest-gate-off na raiz do repo → desliga naquele repo
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 */
function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * Tenta rodar git check-ignore no arquivo. Se não está ignorado, retorna false.
 */
function estaGitignorado(dir, arquivo) {
  try {
    execFileSync("git", ["-C", dir, "check-ignore", arquivo], {
      stdio: "ignore",
    });
    return true; // arquivo está ignorado (exit 0 de check-ignore)
  } catch {
    return false; // arquivo NÃO está ignorado (exit 1 de check-ignore)
  }
}

/**
 * Detecta se o arquivo **em disco** tem o marcador que dispensa a conferência.
 * Marcador: qualquer linha contendo `rainforest-gate: dados-de-exemplo`.
 *
 * LEITURA DO DISCO, não do conteúdo que chega: isto fecha dois furos:
 *   - Edit no arquivo com marcador passa, mesmo se new_string não o tem;
 *   - Write de arquivo novo com marcador embutido é barrado, porque não tem arquivo em disco.
 *
 * Arquivo inexistente, sem permissão ou erro de leitura → sem marcador → segue para
 * conferência. Errar para o lado de conferir, nunca de liberar.
 */
function temMarcadorDados(caminhoDoArquivo) {
  try {
    const conteudo = fs.readFileSync(caminhoDoArquivo, "utf8");
    return /rainforest-gate:\s*dados-de-exemplo/i.test(conteudo);
  } catch {
    // Arquivo inexistente, sem permissão, ou erro de leitura: sem marcador
    return false;
  }
}

/**
 * Roda conferir-publicacao.cjs em modo JSON e retorna o resultado parseado.
 * Retorna { achados: [...], cego: [...] } ou null se não conseguir rodar.
 *
 * O conferir-publicacao.cjs sai com exit 2 quando acha dados sensíveis,
 * então precisamos capturar a saída mesmo quando há erro.
 */
function conferirConteudo(conteudo) {
  try {
    const scriptPath = path.join(__dirname, "..", "scripts", "conferir-publicacao.cjs");
    const output = execFileSync("node", [scriptPath, "-", "--json"], {
      input: conteudo,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return JSON.parse(output);
  } catch (e) {
    // execFileSync lança erro quando exit != 0. Tentamos pegar o stdout do erro.
    if (e.stdout) {
      try {
        return JSON.parse(e.stdout);
      } catch {
        return null;
      }
    }
    return null;
  }
}

/**
 * Formata a mensagem de bloqueio com os achados.
 */
function mensagemBloqueio(achados, arquivo) {
  let msg = `BLOQUEADO pelo gate de publicação do rainforest-mind.\n\n` +
    `Arquivo: ${arquivo}\n` +
    `Razão: este arquivo é versionado (rastreado por git) e contém dados sensíveis.\n\n` +
    `Trechos encontrados:\n`;

  for (const a of achados) {
    msg += `\n  linha ${a.linha}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}\n`;
    msg += `    ${a.o_que}\n`;
    msg += `    → ${a.faca}\n`;
  }

  msg += `\n\nArquivos versionados em repo público não têm como "desaparecer". `;
  msg += `Filter-branch\nremove de uma branch, mas em rede de fork o objeto continua `;
  msg += `servido por SHA\ne só o Support do GitHub consegue remover do storage da rede.\n`;
  msg += `Corrija o conteúdo e rode de novo.\n\n` +
    `ATENÇÃO — PreToolUse aborta a CHAMADA INTEIRA, não só a ferramenta:\n` +
    `  Um 'git add X && git commit' bloqueado não rodou o 'git add'; o índice fica\n` +
    `  com a versão velha e o gate repete o achado depois da correção, parecendo\n` +
    `  que a edição não gravou. Separe: 'git add', verifique com 'git show :<arquivo>',\n` +
    `  depois 'git commit'.\n\n` +
    `As duas saídas de emergência NÃO valem no MESMO comando:\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente: precisa estar na sessão (export),\n` +
    `    não funciona como prefixo inline ('RAINFOREST_GATE_OFF=1 git commit');\n` +
    `  - arquivo .rainforest-gate-off: é conferido ANTES do hook rodar, então\n` +
    `    'touch .rainforest-gate-off && git commit' é bloqueado (usa outro 'git add' depois).\n\n` +
    `Se isto é falso positivo legítimo (teste com dado fake, documentação de formato),\n` +
    `você tem duas saídas:\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessão (desliga na sessão inteira);\n` +
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga naquele repo).\n`;

  return msg;
}

function bloqueia(achados, arquivo) {
  process.stderr.write(mensagemBloqueio(achados, arquivo));
  process.exit(2);
}

/**
 * O comando é um `git commit`?
 *
 * Casa `git commit`, `git -C <dir> commit`, `git commit -am "x"`. NÃO casa
 * `git commit-tree` nem a palavra "commit" em prosa, porque o \b depois de
 * `commit` exige fim de TOKEN e o `git` tem de vir antes.
 * O `\b` que estava aqui casava DENTRO de `commit-tree`, porque `-` e fronteira
 * de palavra — a bateria pegou, e por isso o lookahead e por espaco ou fim.
 */
const RE_GIT_COMMIT = /\bgit\s+(?:(?:-[A-Za-z]\s+\S+|--[a-z-]+(?:=\S+)?|-[A-Za-z]+)\s+)*commit(?=\s|$)/;

/** `-a`, `-am`, `--all`: o commit leva o que está no WORKTREE, não no índice. */
const RE_COMMIT_TUDO = /(?:^|\s)(?:--all\b|-[A-Za-z]*a[A-Za-z]*\b)/;

/**
 * Confere se um achado já existe num arquivo de um dos pais deste commit.
 *
 * Pais são HEAD (se existir) e MERGE_HEAD (se um merge estiver em progresso).
 * Se a linha do achado já estava lá, não é conteúdo novo — isenta.
 */
function achadoJaEstaNoPai(dir, nome, a) {
  const linhaDoAchado = a.linha;
  const pais = [];

  // HEAD é o commit atual
  try {
    const head = git(dir, ["rev-parse", "HEAD"]);
    if (head) pais.push(head);
  } catch {}

  // MERGE_HEAD é o commit sendo mergeado (pode haver mais de um em merge octopus)
  // Usa git rev-parse --git-path MERGE_HEAD para funcionar em worktree linkado
  try {
    const mergeHeadPath = git(dir, ["rev-parse", "--git-path", "MERGE_HEAD"]);
    if (mergeHeadPath && fs.existsSync(mergeHeadPath)) {
      const mergeHeads = fs.readFileSync(mergeHeadPath, "utf8").trim().split("\n");
      for (const h of mergeHeads) {
        if (h.trim()) pais.push(h.trim());
      }
    }
  } catch {}

  // Obtém conteúdo do índice (staged content)
  // Normaliza separadores para forward slash (git show espera isto)
  const nomeNormalizado = nome.replace(/\\/g, "/");
  let conteudoAtual = git(dir, ["show", `:${nomeNormalizado}`]);
  if (conteudoAtual === null) {
    // Se não estiver no índice, tenta do disco
    try {
      conteudoAtual = fs.readFileSync(path.join(dir, nome), "utf8");
    } catch {
      return false;
    }
  }

  const linhasAtual = conteudoAtual.split("\n");
  const linhaAtualContent = linhasAtual[linhaDoAchado - 1];
  if (!linhaAtualContent) return false; // linha não existe

  const linhaAtualTrimmed = linhaAtualContent.trim();

  // Confere cada pai
  for (const pai of pais) {
    const conteudoPai = git(dir, ["show", `${pai}:${nomeNormalizado}`]);
    if (conteudoPai === null) continue; // arquivo não existia neste pai

    const linhasPai = conteudoPai.split("\n");

    // Procura a mesma linha (trimmed) em qualquer posição do arquivo pai
    if (linhasPai.some(l => l.trim() === linhaAtualTrimmed)) {
      return true; // encontrou a mesma linha no pai
    }
  }

  return false;
}

/**
 * O que ESTE commit levaria, e o conteúdo exato que iria para o objeto.
 *
 * A distinção índice-vs-worktree não é preciosismo: `git commit` leva o que
 * está no ÍNDICE, e `git commit -a` leva o que está no worktree. Conferir o
 * arquivo em disco num commit normal aprovaria (ou reprovaria) conteúdo que não
 * é o que vai ser gravado — que é exatamente a classe de erro que este arquivo
 * inteiro existe para não cometer.
 */
function arquivosQueVaoParaOCommit(dir, cmd) {
  const levaWorktree = RE_COMMIT_TUDO.test(cmd);
  const lista = git(dir, ["diff", "--cached", "--name-only", "--diff-filter=ACMR"]);
  const nomes = new Set((lista || "").split("\n").map((s) => s.trim()).filter(Boolean));

  if (levaWorktree) {
    const modificados = git(dir, ["diff", "--name-only", "--diff-filter=ACMR"]);
    for (const n of (modificados || "").split("\n").map((s) => s.trim()).filter(Boolean)) nomes.add(n);
  }

  const saida = [];
  for (const nome of nomes) {
    let conteudo = null;
    if (levaWorktree) {
      try { conteudo = fs.readFileSync(path.join(dir, nome), "utf8"); } catch { conteudo = null; }
    } else {
      // `git show :<caminho>` devolve o conteúdo do ÍNDICE, que é o que o commit
      // vai gravar. Não é o mesmo que ler o arquivo do disco.
      conteudo = git(dir, ["show", `:${nome}`]);
    }
    if (conteudo === null) continue;
    // Binário não passa por regex de telefone sem gerar ruído; o \0 é o teste
    // que o próprio git usa para decidir "Binary files differ".
    if (conteudo.includes("\u0000")) continue;
    saida.push({ nome, conteudo });
  }
  return saida;
}

/**
 * A trava no COMMIT — Issue #165.
 *
 * O gate acima cobre `Write`, `Edit` e `MultiEdit`, e é o que dá o aviso cedo.
 * Mas ele cobre a FERRAMENTA, não o EFEITO: em 2026-09-02 o mesmo conteúdo
 * sensível entrou no repositório sem ele ver, escrito por um `fs.writeFileSync`
 * dentro de um script node invocado pelo Bash. Nenhum evento de `Write` foi
 * emitido, nenhum `PreToolUse` disparou. `sed -i`, heredoc e `python - <<PY`
 * têm o mesmo caminho livre — e escrita por script é justamente a que se usa em
 * mudança de lote, que é onde o volume passa sem ninguém ler linha a linha.
 *
 * Por que no commit e não numa checagem de `Bash`: ler a linha de comando não
 * diz o que o script vai escrever. `node edita.mjs` é opaco. O commit é o único
 * ponto por onde tudo passa, independentemente de como o arquivo foi escrito —
 * e é o ponto em que o dado deixa de ser local e vira histórico.
 *
 * As três isenções são as mesmas do gate de escrita, de propósito: um arquivo
 * que passa por `Write` e reprova no `commit` seria uma trava contradizendo a
 * outra, e o usuário aprenderia a desligar as duas.
 */
function conferirCommit(ev, cwdDoEvento) {
  const cmd = ev.tool_input && ev.tool_input.command;
  if (typeof cmd !== "string" || !RE_GIT_COMMIT.test(cmd)) process.exit(0);

  const gitTop = git(cwdDoEvento, ["rev-parse", "--show-toplevel"]);
  if (!gitTop) process.exit(0);

  try {
    if (fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) process.exit(0);
  } catch {}

  for (const { nome, conteudo } of arquivosQueVaoParaOCommit(gitTop, cmd)) {
    const absoluto = path.join(gitTop, nome);
    if (estaGitignorado(gitTop, absoluto)) continue;
    // O marcador é procurado no conteúdo QUE VAI SER COMMITADO, não no disco:
    // arquivo que ganhou o marcador só no worktree não pode dispensar a
    // conferência do que já está no índice.
    if (/rainforest-gate:\s*dados-de-exemplo/i.test(conteudo)) continue;

    const resultado = conferirConteudo(conteudo);
    if (resultado && resultado.achados && resultado.achados.length) {
      const achadosAbloquear = [];
      const dir = gitTop; // para a mutação: a linha tem que ser exata
      for (const a of resultado.achados) {
        if (achadoJaEstaNoPai(dir, nome, a)) continue;
        achadosAbloquear.push(a);
      }

      if (achadosAbloquear.length > 0) {
        process.stderr.write(
          `\nEste conteudo entraria no COMMIT, e o gate de escrita nao o viu —\n` +
          `ele cobre Write/Edit, e este arquivo pode ter sido escrito por script\n` +
          `(node, sed, heredoc). Issue #165.\n`
        );
        bloqueia(achadosAbloquear, absoluto);
      }
    }
  }
  process.exit(0);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegível nunca trava o trabalho do usuário
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  // Toggle do setup: quem não quer este gate num repositório pode desligá-lo por
  // `.rainforest/config.json` do projeto.
  try { if (!require("./lib/config.cjs").ligado("gate-publicacao", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  const nome = ev.tool_name;

  // O commit é o ponto por onde tudo passa (Issue #165). Vem ANTES do filtro de
  // ferramentas de escrita porque `Bash` nunca esteve nele.
  if (nome === "Bash" || nome === "PowerShell") conferirCommit(ev, cwdDoEvento);

  if (!FERRAMENTAS_DE_ESCRITA.has(nome)) process.exit(0);

  const entrada = ev.tool_input || {};
  let arquivo = null;
  let conteudo = null;

  if (nome === "Write" && typeof entrada.file_path === "string" && typeof entrada.content === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.content;
  } else if (nome === "Edit" && typeof entrada.file_path === "string" && typeof entrada.new_string === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.new_string;
  } else if (nome === "MultiEdit") {
    // MultiEdit passa um array de edits. Conferir cada um.
    const edits = Array.isArray(entrada.edits) ? entrada.edits : [];
    for (const edit of edits) {
      if (typeof edit.file_path === "string" && typeof edit.new_string === "string") {
        // Confere este arquivo/conteúdo
        const a = edit.file_path;
        const c = edit.new_string;
        const dir = dirDe(a);
        const gitTop = git(dir, ["rev-parse", "--show-toplevel"]);
        if (!gitTop) continue; // fora de repo git

        if (estaGitignorado(dir, a)) continue; // gitignorado passa

        if (temMarcadorDados(a)) continue; // marcador de dados-de-exemplo passa

        const resultado = conferirConteudo(c);
        if (resultado && resultado.achados && resultado.achados.length) {
          bloqueia(resultado.achados, a);
        }
      }
    }
    process.exit(0);
  } else {
    process.exit(0);
  }

  if (!arquivo || !conteudo) process.exit(0);

  // Determina o diretório onde o arquivo vai ficar
  const dir = dirDe(arquivo);

  // Confere se está dentro de um repo git
  const gitTop = git(dir, ["rev-parse", "--show-toplevel"]);
  if (!gitTop) process.exit(0); // fora de repo git: passa

  // Confere se é arquivo gitignorado
  if (estaGitignorado(dir, arquivo)) process.exit(0); // ignorado passa

  // Confere se tem marcador de dados-de-exemplo (para testes de bateria)
  if (temMarcadorDados(arquivo)) process.exit(0); // marcador dispensa conferência

  // Confere se o arquivo está na raiz do repo ou em subdiretório
  try {
    if (fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) process.exit(0);
  } catch {}

  // Roda a conferência de publicação
  const resultado = conferirConteudo(conteudo);
  if (resultado && resultado.achados && resultado.achados.length) {
    bloqueia(resultado.achados, arquivo);
  }

  process.exit(0);
}

function dirDe(alvo) {
  try {
    return fs.existsSync(alvo) && fs.statSync(alvo).isDirectory() ? alvo : path.dirname(alvo);
  } catch {
    return path.dirname(alvo);
  }
}

if (require.main === module) main();
