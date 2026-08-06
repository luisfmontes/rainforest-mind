#!/usr/bin/env node
// SessionStart hook: injeta as regras rainforest-mind + foco declarado em toda sessão.
const fs = require('fs');
const path = require('path');

// Dados (FOCO/IDEIAS) vivem no repo de trabalho, não na cópia em cache do plugin.
const DATA_ROOT = 'C:\\Projetos\\rainforest-mind';
const ROOT = fs.existsSync(DATA_ROOT) ? DATA_ROOT : path.resolve(__dirname, '..');

function readSafe(p) {
  try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; }
}

const foco = readSafe(path.join(ROOT, 'FOCO.md'));
const skill = readSafe(path.join(ROOT, 'skills', 'rainforest-mind', 'SKILL.md'));

// Aviso de revisão bimestral a partir da linha "Última revisão: YYYY-MM-DD"
let revisao = '';
const m = skill.match(/Última revisão:\s*(\d{4}-\d{2}-\d{2})/);
if (m) {
  const dias = Math.floor((Date.now() - new Date(m[1]).getTime()) / 86400000);
  if (dias > 60) {
    revisao = `\n⚠ A skill rainforest-mind não é revisada há ${dias} dias (limite: 60). Avise o Luís que está na hora de revisá-la.`;
  }
}

const regras = skill.split('## As regras')[1]?.split('## Comando')[0]?.trim() || '';

// Sessões paralelas (heartbeat: prompt_ts = o Luís agiu, stop_ts = Claude
// terminou o turno e está esperando)
let sessoes = '';
try {
  const state = JSON.parse(fs.readFileSync(path.join(ROOT, 'sessoes.json'), 'utf8'));
  const agora = Date.now();
  const linhas = Object.entries(state)
    .filter(([, s]) => agora - Math.max(s.prompt_ts || 0, s.stop_ts || 0) < 6 * 3600 * 1000)
    .map(([id, s]) => {
      const p = s.prompt_ts || 0, t = s.stop_ts || 0;
      const min = (x) => Math.round((agora - x) / 60000);
      const status = p > t
        ? `Claude trabalhando (turno em curso há ${min(p)} min)`
        : `esperando o Luís há ${min(t || p)} min`;
      return `- ${s.cwd || '(pasta desconhecida)'} — ${status}`;
    });
  if (linhas.length) {
    const oci = (foco.match(/Ociosidade máxima:\s*(\d+)\s*min/i) || [])[1] || '45';
    sessoes = `\n## Outras sessões recentes (radar multi-janela)\n${linhas.join('\n')}\n` +
      `Se alguma dessas sessões está no projeto do foco ativo, o radar DESTA sessão fica leve (trabalho paralelo é normal). ` +
      `Ocioso = "esperando o Luís" — Claude trabalhando nunca conta. ` +
      `O alerta que importa: sessão do projeto do foco esperando o Luís há ${oci}+ min enquanto as demais trabalham — avisar uma vez ("a janela do foco esfriou").\n`;
  }
} catch {}

console.log(`RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do Luís (perfil 2e).

## Regras (aplicar em toda resposta)
${regras}

## Foco declarado
${foco || '(nenhum foco declarado — sugira /foco <texto> se o Luís disser no que precisa entregar)'}
${sessoes}${revisao}
Arquivos de apoio: ${ROOT}\\FOCO.md e ${ROOT}\\ideias.jsonl (uma ideia por linha)`);
