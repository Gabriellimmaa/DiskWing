> Versão pública sanitizada do registro original. Identificadores e evidências pessoais ficam no arquivo privado de migração. Este registro histórico não substitui o estado atual do projeto.

# CacheSSD 0.1.0: implementação e validação local

Registro de 9 de novembro de 2026. Entrega para Apple Silicon, com macOS 14 ou posterior. Validado neste Mac com macOS 26.5.2 e Swift 6.3.3. Trata-se de uma versão local inicial; a distribuição pública e a avaliação com outras pessoas permanecem no roadmap.

## O que foi entregue

- Aplicativo nativo com visão geral, explorador de espaço, busca, maiores arquivos, navegação entre pastas, Finder, histórico, ajustes e menu na barra do macOS.
- Análise por metadados, com progresso, cancelamento, limites de consumo e indicação de leituras parciais. Links e outros volumes não são percorridos automaticamente. Tamanho lógico e blocos alocados são apresentados separadamente.
- Catálogo de npm, Bun, CocoaPods, pip, Homebrew, Gradle e uv. Cada migração tem revisão própria, cópia por geração, hashes SHA-256, conferência de estabilidade da origem, verificação da ferramenta e registro de recuperação.
- Direcionamento no terminal zsh por comando, respeitando configurações explícitas. O SSD é identificado pelo UUID e pelo ponto de montagem atual. A ausência do SSD faz novas execuções usarem os locais padrão.
- Integração do terminal com backup e desativação; revisão do ajuste de temporários; opção de restaurar o local padrão do Xcode; preparação para ejeção; opção de início de sessão.
- Ações de arquivos pessoais com revisão: enviar à Lixeira ou copiar para outro destino, conferir o conteúdo e enviar a origem à Lixeira. A aplicação não esvazia a Lixeira.
- Código-fonte, plano v1 preservado, roadmap e instruções de recuperação.

Nenhum cache pessoal foi migrado nesta entrega. A integração do terminal e a opção do Xcode não foram ativadas. Não foram alterados perfis, senhas, cookies, histórico ou caches do Chrome. O inventário local não representa espaço já liberado nem promessa de recuperação integral.

## Ajustes de segurança em relação ao plano v1

Bun e uv podem manter instalações dependentes de links para o cache. Nesta versão, a opção de remover suas origens fica desativada. Uma cópia externa pode atender novas execuções compatíveis; a economia inicial dessas duas origens é zero. Configurações personalizadas de links também impedem o direcionamento automático. Essa decisão preserva instalações existentes e deve ser revista somente com testes específicos de cada modalidade. Referências: [Bun global cache](https://bun.sh/docs/pm/global-cache) e [uv link-mode](https://docs.astral.sh/uv/reference/settings/#link-mode).

A liberação da origem está disponível para npm, Gradle, CocoaPods, pip e Homebrew, somente depois das verificações. SDKs, emuladores, projetos, executáveis locais do npx e dados do navegador permanecem fora da seleção.

Uma movimentação pessoal mantém a origem recuperável na Lixeira. Portanto, o espaço interno só será recuperado após a pessoa revisar e esvaziar a Lixeira no Finder. Caches reconhecidos seguem a operação específica indicada na revisão.

## Verificações concluídas

A execução final terminou com **26 testes, zero falhas e zero testes ignorados**. Foram usadas pastas temporárias isoladas no SSD, sem migrar caches reais. O registro integral acompanha a entrega em arquivo privado de migração; os resultados públicos estão em ../context/MIGRATION-2026-11-09.md.

Os testes cobrem contagem de hard links, links externos, limites e resultados parciais da análise; cópia e conferência de conteúdo; cancelamento; SSD ausente, UUID divergente e falta de espaço simulados; origem preservada após interrupção; bloqueio com arquivo aberto; proteção do navegador e dados de aplicativos; configurações ilegíveis; preferências de projeto; prioridade de variáveis explícitas; instalação e remoção da integração; alteração manual de variáveis durante a sessão; preservação de permissões e links de arquivos de configuração; regras do Gradle; e preservação das origens de Bun e uv.

Também foram executadas verificações nativas em cópias isoladas: `npm cache verify`, `bun pm cache`, `pod cache list --short`, `python3 -m pip cache info`, `uv cache dir`, `brew --cache` e `gradle --version --no-daemon`, usando uma distribuição do Gradle já existente. Isso valida a abertura das integrações; não equivale a compilar projetos completos com cada ferramenta. A detecção de executáveis foi ajustada para considerar as instalações de Node e Ruby do usuário; a instalação funcional de CocoaPods foi localizada e passou pela execução final.

A compilação de produção e a verificação estrita da assinatura local foram concluídas. O aplicativo foi instalado em `~/Applications/CacheSSD.app`. A assinatura é ad hoc, sem notarização pública.

Na interface foram verificados navegação pelas seções, escolha de pasta, análise de arquivos de teste, busca, lista dos maiores arquivos, abertura de subpasta e retorno, revisão da integração e revisão de migração. As revisões foram canceladas sem aplicar mudanças pessoais. Um arquivo de teste descarregado pelo iCloud foi corretamente bloqueado para movimentação, com orientação para baixá-lo no Finder. A revisão de Bun apresentou a origem como preservada.

## Limites e verificações ainda necessárias

- Ausência, falta de espaço e interrupções foram exercitadas em testes controlados. Não foi retirado fisicamente o cabo durante escrita, renomeado o SSD real ou alteradas suas permissões.
- Ainda faltam instalações completas de dependências e compilações de projetos temporários em cada ferramenta, com SSD conectado, desconectado e sem internet. As verificações nativas não substituem esses cenários.
- Não foram aplicadas a integração real do terminal, a mudança real do Xcode, a inicialização automática nem uma migração de dados pessoais. Esses fluxos têm revisão no aplicativo.
- A preparação para ejeção depende da autorização do macOS e de arquivos em uso. Não garante continuidade de um processo depois de uma desconexão física.
- A árvore é limitada a 200 mil itens e 80 níveis; a exibição retém até 120 filhos por pasta e 60 maiores arquivos. A interface indica truncamentos e leituras incompletas. Até 50 resumos e 150 operações são mantidos localmente.
- Não há atualização contínua por eventos, comparação automática após sete dias, notificações de crescimento, identificação de duplicados, desinstalação completa nem migração de bibliotecas.
- Ainda faltam testes em outros Macs e versões do macOS, revisão de acessibilidade completa, Developer ID, notarização, atualização assinada, ensaio de desinstalação pública e beta com cinco usuários gerais e cinco desenvolvedores.

O disco interno teve pouco espaço durante o trabalho. A compilação e os testes finais foram executados no SSD externo. A pasta de trabalho em Documentos também sofre descarregamento pelo iCloud; por isso a compilação usa uma cópia estável do código no SSD. O pacote de fontes entregue corresponde a essa cópia final, sem dependências externas de pacotes.

## Primeira utilização

Abra CacheSSD e confira **Caches e SSD**. Revise uma ferramenta por vez e leia se a origem será mantida ou liberada. Depois, revise a integração do terminal e abra uma nova sessão. Nenhuma mudança de cache acontece só por abrir o aplicativo. Use **Preparar para ejetar** antes de desconectar o SSD.

Se uma operação falhar, preserve a origem e os registros em `~/Library/Application Support/CacheSSD`. O histórico mostra a cópia de recuperação e operações interrompidas. As instruções de recuperação completas estão no [README](../../README.md).
