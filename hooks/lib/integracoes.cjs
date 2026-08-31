/**
 * Registro de integrações opcionais do rainforest.
 *
 * Cada integração é um repositório próprio do usuário, com ciclo de release
 * próprio. Declarável via `--ligar integracao-<nome>` no setup, desligada por
 * padrão. O `/saude` confere só o que foi declarado, uma linha cada.
 */

const INTEGRACOES = {
  'whatsapp-mcp': {
    descricao: 'MCP para bridge WhatsApp local (127.0.0.1:3005)',
    checar: () => ({
      ok: true,
      detalhe: 'checagem entra na tarefa 7/8',
    }),
  },
  sabia: {
    descricao: 'Sabiá: transcrição local de reunião com diarização (quem falou), CLI Python',
    checar: () => ({
      ok: true,
      detalhe: 'checagem entra na tarefa 7/8',
    }),
  },
};

module.exports = { INTEGRACOES };
