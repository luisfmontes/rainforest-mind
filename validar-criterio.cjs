const fs = require('fs');
const path = require('path');
const lib = require('./hooks/lib/contexto-sessao.cjs');

// Lê o FOCO.md real
const focoText = fs.readFileSync('C:/Users/Luis/.rainforest/FOCO.md', 'utf8');

// Extrai a pasta do foco (primeira pasta da lista)
const pastasMatch = focoText.match(/^Pastas:\s*(.+)$/m);
if (!pastasMatch) {
  console.error('ERRO: Pastas: não encontrado no FOCO.md real');
  process.exit(1);
}
const pastasText = pastasMatch[1];
const pastas = pastasText.split(',').map(s => s.trim()).filter(Boolean);
const pastaPrincipal = pastas[0];

if (!pastaPrincipal) {
  console.error('ERRO: Nenhuma pasta encontrada no campo Pastas:');
  process.exit(1);
}

console.log('Pasta principal do foco:', pastaPrincipal);

// Monta uma sessão viva na subpasta do foco
const sessionCwd = path.join(pastaPrincipal, 'templates/FIN/Gestao_Projetos');
const agora = Date.now();
const sessoes = [{
  cwd: sessionCwd,
  prompt_ts: agora - 1000, // Sinal humano há 1 segundo (dentro da ociosidade máxima)
}];

// Config vazio (sem expediente configurado)
const config = {};

// Chama computarVeredito
const veredito = lib.computarVeredito(focoText, sessoes, config, agora);

console.log('\n===== RESULTADO =====');
console.log(veredito);
console.log('===== FIM =====\n');

// Verifica critério de sucesso
const temVeredito = veredito.includes('NÃO cobrar desvio de escopo nesta sessão');
const temMotivoFoco = veredito.includes('foco ativo em outra janela');
const temAnuncioExpediente = veredito.includes('expediente: ausente no config.json');

console.log('VERIFICAÇÃO DO CRITÉRIO:');
console.log('✓ Contém veredito:', temVeredito);
console.log('✓ Veredito menciona "foco ativo em outra janela":', temMotivoFoco);
console.log('✓ Contém anúncio sobre "expediente":', temAnuncioExpediente);

if (temVeredito && temMotivoFoco && temAnuncioExpediente) {
  console.log('\n✅ CRITÉRIO DE SUCESSO ATENDIDO: veredito E anúncio aparecem juntos');
  process.exit(0);
} else {
  console.log('\n❌ CRITÉRIO DE SUCESSO NÃO ATENDIDO');
  process.exit(1);
}
