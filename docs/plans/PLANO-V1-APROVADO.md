> Versão pública sanitizada do registro original. Identificadores e evidências pessoais ficam no arquivo privado de migração. Este registro histórico não substitui o estado atual do projeto.

# CacheSSD migração seletiva com retorno seguro ao Mac

Plano v1 aprovado em 8 de novembro de 2026 e preservado em 9 de novembro. O conteúdo abaixo mantém as decisões aprovadas. O registro de implementação é separado; aprovação do plano não significa que migrações pessoais já tenham sido executadas.

## Objetivo e decisões confirmadas

Criar um aplicativo macOS na barra de menus para usar o SSD externo nos caches compatíveis e manter o Mac funcionando quando ele estiver desconectado.

O comportamento combinado será:

- A troca ocorre ao iniciar a ferramenta. Programas já abertos podem precisar ser encerrados e reabertos.
- Sem SSD, as ferramentas usam caches locais e podem baixar dependências novamente.
- SDKs e dados dos emuladores ficam no Mac, preservando sua disponibilidade.
- Chrome, senhas, cookies, histórico, perfis, credenciais e projetos ficam fora da migração.
- Não haverá espelhamento completo dos caches: manter duas cópias permanentes eliminaria boa parte da economia de espaço.

O inventário inicial identificou caches candidatos; o volume depende de cada Mac. O espaço efetivamente liberado será medido após a migração, pois arquivos compartilhados e cópias APFS podem reduzir esse ganho. Essa estimativa corresponde à inspeção de 8 de novembro e deve ser atualizada antes de qualquer operação.

## Aplicativo e funcionamento

Aplicativo local em SwiftUI/AppKit, instalado no armazenamento interno, com início de sessão pelo mecanismo oficial do macOS. O aplicativo e seu auxiliar continuarão disponíveis sem o SSD.

A interface em português mostrará SSD conectado, ausente ou indisponível para escrita; local escolhido para cada ferramenta; execuções ainda usando o local anterior; espaço ocupado, espaço realmente liberado e migrações pendentes. As ações serão Migrar caches, Preparar para ejetar, Usar somente o Mac e Desativar integração.

O SSD será identificado pelo identificador permanente e pelo ponto de montagem atual. O aplicativo não confiará somente no nome nem criará uma pasta substituta quando o disco estiver ausente.

O direcionamento usará configurações nativas, sem substituir pastas gerais do macOS por links para o SSD.

| Ferramenta | Integração | Conteúdo inicial |
|---|---|---|
| npm | npm_config_cache | Cache de pacotes; preservar executáveis locais do npx |
| Gradle | GRADLE_USER_HOME | Caches; configurações, JDKs e distribuições locais disponíveis |
| Bun | BUN_INSTALL_CACHE_DIR | Cache de pacotes |
| CocoaPods | CP_CACHE_DIR | Downloads e cache de Pods |
| pip | PIP_CACHE_DIR | Downloads e pacotes compilados |
| uv | UV_CACHE_DIR | Cache, preservando ambientes e executáveis em uso |
| Homebrew | HOMEBREW_CACHE | Downloads |

Esses mecanismos evitam mover instalações inteiras. [Bun](https://bun.sh/docs/pm/global-cache), [CocoaPods](https://github.com/CocoaPods/CocoaPods/blob/master/lib/cocoapods/config.rb), [Gradle](https://docs.gradle.org/current/userguide/directory_layout.html).

Um auxiliar instalado no Mac escolherá caminhos antes de cada comando no terminal zsh. A escolha valerá para o comando e seus filhos, incluindo ./gradlew. O aplicativo oferecerá um executor com o mesmo ambiente. Aplicativos abertos por outros caminhos continuarão usando suas configurações locais, com essa cobertura explícita na interface.

Preferências personalizadas serão preservadas. Se o auxiliar falhar ou o SSD estiver indisponível, novas execuções usarão armazenamento local.

Será removido o direcionamento incondicional de temporários ao SSD. O Xcode terá opção de retornar ao local padrão dos arquivos de compilação; compilações iniciadas pelo executor poderão receber um destino específico. Caches do Chrome, do sistema, do Expo e executáveis usados por serviços do Codex ficam locais na primeira versão.

## Migração e troca entre os discos

Na preparação, registrar tamanhos, configurações, processos em uso e espaço disponível; criar pasta exclusiva para o Mac e usuário no SSD; salvar configurações originais e registro de recuperação no armazenamento interno. Nenhum processo será finalizado à força.

Para cada ferramenta:

1. Aguardar ficar inativa.
2. Copiar o cache para área temporária no SSD, preservando permissões e links internos válidos.
3. Conferir integridade, conteúdo e estabilidade da origem. Alterações adiam a operação.
4. Ativar o destino e executar a validação própria da ferramenta.
5. Liberar arquivos locais somente após a validação, mantendo cópia verificada no SSD.

Começar por npm e Bun; depois CocoaPods, pip, Homebrew, Gradle e uv. Cada ferramenta terá registro independente. No Gradle, copiar caches compatíveis sem bloqueios ativos e manter componentes necessários ao funcionamento local. [Regras de cópia](https://docs.gradle.org/current/userguide/dependency_caching.html).

Com o SSD conectado, novas execuções passam a utilizá-lo; processos existentes mantêm seu destino. Preparar para ejetar suspende novas execuções externas, identifica dependências, aguarda encerramento e solicita a ejeção. Sem SSD, usar diretórios locais e recriar caches quando necessário. Ao reconectar, voltar ao cache do SSD sem mesclar automaticamente bancos, índices ou bloqueios. A limpeza de caches locais crescidos usará procedimentos próprios das ferramentas, somente quando inativas.

Retirar o cabo durante uma operação pode interrompê-la. As próximas execuções retornarão ao local disponível; não há promessa de continuidade do processo interrompido. [Avisos de desmontagem da Apple](https://developer.apple.com/documentation/appkit/nsworkspace/willunmountnotification).

## Validação recuperação e entrega

Testar reutilização de caches no SSD; inicialização sem SSD; dependência com cache local vazio e internet; conexão com ferramentas abertas; ejeção com arquivos em uso; SSD renomeado, sem escrita ou sem espaço; cópia interrompida e reinício; falha do auxiliar; desativação e retorno aos padrões; preservação dos dados do Chrome.

Usar projetos temporários, sem alterar projetos existentes. Começar com duas ferramentas antes de incluir as demais.

A entrega incluirá aplicativo, código-fonte, instruções de recuperação e relatório dos caches migrados, itens preservados e espaço efetivamente liberado. A desativação removerá a integração e restaurará padrões locais sem apagar dados do navegador ou dos emuladores.
