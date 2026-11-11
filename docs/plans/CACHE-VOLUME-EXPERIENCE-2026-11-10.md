# Caches no SSD e exploração de volumes

Plano solicitado e aprovado pelo mantenedor em 10/11/2026. Este incremento
substitui a experiência fragmentada do build 8, preservando o plano histórico,
a identidade Lift, PT/EN e todos os formatos/identificadores existentes.

## Contrato de produto

- Dois fluxos principais: Explorar volumes e Caches no SSD.
- Sem destinos de cache registrados: mostrar Nenhum cache transferido, mesmo
  que exista SSD escolhido ou integração marcada.
- Escolher SSD → analisar caches por aplicativo → revisar → transferir e
  ativar → acompanhar resultado. Preparação de origem vazia faz parte do fluxo.
- Selecionar por padrão somente integrações qualificadas para transferência
  completa; cópia com origem retida não conta como espaço liberado nem sucesso.
- Cobertura ampla, incluindo aplicativos gráficos abertos normalmente pelo Dock,
  com exceções e quantidades locais explícitas. A matriz inicial é Chrome,
  Cursor, Xcode e Safari. Ao menos um aplicativo gráfico real deve ser qualificado.
- Sem SSD, os programas continuam funcionando; cache local temporário é permitido.
  Processos abertos podem precisar reabrir. Não prometer continuidade após cabo
  retirado durante operação nem mesclar gerações arbitrariamente.
- Árvore e treemap sincronizados sobre todo o volume acessível; selecionar volume
  não altera o SSD dos caches. Lixeira em qualquer volume pessoal elegível, sem
  exclusão permanente ou enfraquecimento das proteções de dados.

## Caches

Cada provider descobre o destino efetivo e separa cache de perfis, cookies,
senhas, projetos, SDKs e instalações. Preferir configuração nativa; admitir link
individual somente para pasta reconhecida e qualificada. Nunca redirecionar
Library/Caches inteira, contornar sandbox ou mudar preferências do mantenedor
apenas para testar. O novo plano permite caches Chrome qualificados, preservando
todos os seus dados de perfil; isso substitui a exclusão histórica de cache Chrome.

CacheTransferPlan é uma revisão por aplicativo e raiz de cache, incluindo fonte,
destino, consequências, necessidade de fechar/reabrir, elegibilidade de liberação
e exceção. Cada operação usa lease, checkpoint, verificação de cópia/estabilidade,
ativação comprovada e recuperação durável. Um erro não desfaz outros apps prontos.

CacheUsageState distingue nenhum destino, transferindo, configurado/aguardando
reabertura ou uso, uso SSD comprovado, local temporário e exceção/erro. Diretório,
link ou flag isolados não são prova de uso. Prova exige leitura/reuso e novas
gravações do aplicativo no SSD, com a origem antiga indisponível no teste.

Uma inicialização especial que força --disk-cache-dir não prova uso normal.
Perfis gerados precisam ter equivalência de resolução demonstrada por fonte/
documentação e teste, ou a qualificação usa ambiente macOS descartável. Nunca
usar perfil real, dados pessoais, configurações Xcode reais ou contas reais.

Na ausência, aplicar apenas fallback testado. Provider sem continuidade segura
fica local e visível como exceção. Na reconexão, conservar temporários e oferecer
revisão única; sem reconciliação nativa segura, arquivar como geração separada no
SSD antes de liberar o Mac. Preservar geração ativa e recuperação; sem merge
genérico nem limpeza automática. Cache novo de versão desconhecida exige prova.

## Volumes e ações

VolumeScanTarget identifica volume/grupo e raízes físicas. Macintosh HD reúne
System/Data comprovadamente do mesmo grupo APFS em namespace único. Preservar
origem física por item, deduplicar aliases/hard links sem tratar clones como
espaço recuperável. Outros mounts são alvos separados. Áreas inacessíveis ou
interrompidas ficam explícitas; completo somente após todas as raízes acessíveis.

Manter SQLite e consultas sob demanda, sem árvore inteira em memória ou corte
visual de itens. Índice novo no SSD APFS escolhido cresce até reserva de 1 GiB;
sem SSD, orçamento interno 512 MiB/piso 256 MiB. Não migrar índice antigo ao abrir.
Fila de diretórios durável e retomada idempotente revalidam diretórios alterados.
Interrupção/espaço insuficiente dão parcial; nunca completar cursor antigo sem
reconciliar mudanças. Proteger/excluir dados do próprio índice contra feedback.

Seleção, navegação e métrica são compartilhadas por árvore/mapa; alocado estimado
é padrão, lógico é alternativo. Outros agrega somente visualmente, com totais
completos e aprofundamento. Todas as ações disponíveis por árvore/teclado.

Trash distinto de Move. Vincular fonte, volume/montagem e item por identidade,
revalidar antes de agir e resolver UUID na recuperação após renomear/remontar.
Proteger roots, sistema, perfis/credenciais/SDKs/instalações e todos os registros,
índices, caches gerenciados e recuperação, inclusive ancestrais. Usar somente
FileManager.trashItem; falha preserva fonte. Para filesystem sem restauração
segura pelo app, manter Trash e recuperação Finder, sem cópia destrutiva.

## UI e referência

Manter native SwiftUI/AppKit, Lift e paleta existente. A mudança visual marcante
é a árvore com mapa; conteúdo operacional usa hierarquia curta, espaços claros,
uma ação principal por etapa e detalhes técnicos expansíveis, sem cartões
decorativos ou opções técnicas fragmentadas.

Adaptar layout squarified e ideias de navegação do DiskPilot no commit
534a70a43b364bcbae1fc5c1f897b5770159052f, com licença/atribuição MIT preservadas.
Não importar scanner em RAM, corte 100 mil, junk, permanent-delete ou analytics.

## Execução e aceite

Worktrees e propriedade exclusiva por frente; coordenação integra UI, traduções,
documentos e ledger. Revisão por outro autor obrigatória. Usar toda capacidade
da sessão, respeitando limite técnico; serializar native/filesystem/scale e merges.

Validar: flags sem destinos; reuso e escrita SSD de app gráfico; fallback/reabrir/
reconectar; origem vazia; falhas/cancelamento/conflitos/checkpoints; preservação de
perfis/dados; grupos APFS, links, mounts, cloud e árvores >1 milhão; índices
desconectados/retomada; Trash externa/remontagem/Finder; PT/EN, mínimo 1050×690,
árvore/treemap e teclado. Usar somente fixtures geradas e volumes descartáveis.

Preservar build 8 instalado e backups. Gerar candidato novo com identidade própria;
nenhuma migração pessoal decorre de implementar/testar. Assinatura, outro Mac,
falhas físicas, humanos e beta continuam separados e publicV1Ready permanece false.
