#!/usr/bin/env node
// @categoria: sensor

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');

// Parse command line arguments manualmente
const raizesOpcao = [];
let maxCandidatos = null;

for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--raiz' && i + 1 < process.argv.length) {
    raizesOpcao.push(process.argv[++i]);
  } else if (process.argv[i] === '--max' && i + 1 < process.argv.length) {
    maxCandidatos = parseInt(process.argv[++i], 10);
  }
}

// Função para buscar arquivos JSONL recursivamente
function buscarArquivosJsonl(dir) {
  const arquivos = [];

  function lerDir(d) {
    try {
      const itens = fs.readdirSync(d);
      for (const item of itens) {
        const p = path.join(d, item);
        try {
          const stat = fs.statSync(p);
          if (stat.isDirectory()) {
            lerDir(p);
          } else if (item.endsWith('.jsonl')) {
            arquivos.push(p);
          }
        } catch (e) {
          // Ignorar erros de stat
        }
      }
    } catch (e) {
      // Ignorar erros de leitura de diretório
    }
  }

  lerDir(dir);
  return arquivos;
}

function lerTranscrices() {
  const candidatos = new Map(); // comando -> candidato object
  let arquivosLidos = 0;
  let totalTool = 0;
  let bloqueados = 0;

  let arquivos = [];

  // Se há --raiz, buscar neles
  if (raizesOpcao.length > 0) {
    for (const raiz of raizesOpcao) {
      arquivos.push(...buscarArquivosJsonl(raiz));
    }
  } else {
    // Senão, procurar no home
    const home = os.homedir();
    try {
      const claudeDirs = fs.readdirSync(home).filter(d => d.startsWith('.claude'));
      for (const dir of claudeDirs) {
        const projectsDir = path.join(home, dir, 'projects');
        if (fs.existsSync(projectsDir)) {
          arquivos.push(...buscarArquivosJsonl(projectsDir));
        }
      }
    } catch (e) {
      // Ignorar erros ao ler home
    }
  }

  for (const arquivo of arquivos) {
    try {
      const conteudo = fs.readFileSync(arquivo, 'utf8');
      const linhas = conteudo.split('\n').filter(l => l.trim());

      const msgs = {}; // id da message assistant -> objeto
      const results = {}; // tool_use_id -> tool_result content

      // Primeira passagem: coletar messages e results
      for (const linha of linhas) {
        try {
          const obj = JSON.parse(linha);

          if (obj.type === 'assistant' && obj.message && obj.message.id) {
            msgs[obj.message.id] = obj.message;
          }

          if (obj.type === 'user' && obj.message && obj.message.content) {
            const conteudoMsg = obj.message.content;
            if (Array.isArray(conteudoMsg)) {
              for (const item of conteudoMsg) {
                if (item.type === 'tool_result') {
                  results[item.tool_use_id] = item.content || '';
                }
              }
            }
          }
        } catch (e) {
          // Ignorar linhas malformadas
        }
      }

      // Segunda passagem: extrair comandos Bash
      for (const linha of linhas) {
        try {
          const obj = JSON.parse(linha);

          if (obj.type === 'assistant' && obj.message && obj.message.content) {
            const conteudoMsg = obj.message.content;
            if (Array.isArray(conteudoMsg)) {
              for (const item of conteudoMsg) {
                if (item.type === 'tool_use' && item.name === 'Bash') {
                  totalTool++;
                  const toolUseId = item.id;
                  const comando = item.input && item.input.command;

                  if (!comando) continue;

                  // Procurar resultado
                  const texto = results[toolUseId];
                  if (texto === undefined) {
                    // Sem result, descartar
                    continue;
                  }

                  // Verificar se bloqueado por hook
                  const bloqueado = /^PreToolUse:[A-Za-z]+ hook error:/.test(texto);
                  if (bloqueado) {
                    bloqueados++;
                    continue;
                  }

                  // Adicionar candidato
                  if (!candidatos.has(comando)) {
                    const contexto = (arquivo.includes('/subagents/') || arquivo.includes('\\subagents\\') || obj.isSidechain)
                      ? 'subagente'
                      : 'principal';
                    const hash = crypto.createHash('sha1').update(comando).digest('hex');
                    const id = hash.substring(0, 8);
                    candidatos.set(comando, { id, comando, contexto });
                  }
                }
              }
            }
          }
        } catch (e) {
          // Ignorar linhas malformadas
        }
      }

      arquivosLidos++;
    } catch (e) {
      // Ignorar arquivos que não conseguem ler
    }
  }

  // Saída dos candidatos
  const candidatosArray = Array.from(candidatos.values());
  const slice = maxCandidatos !== null ? candidatosArray.slice(0, maxCandidatos) : candidatosArray;
  let emitidos = 0;
  for (const candidato of slice) {
    console.log(JSON.stringify(candidato));
    emitidos++;
  }

  // Resumo no stderr
  console.error(`Resumo: ${arquivosLidos} arquivo(s) lido(s), ${emitidos} candidato(s) emitido(s), ${bloqueados} bloqueado(s) por hook`);
  console.error('Aviso: a saída carrega dado local e nunca se commita sem curadoria.');
}

lerTranscrices();
