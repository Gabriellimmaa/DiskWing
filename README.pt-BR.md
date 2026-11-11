# DiskWing

Aplicativo open source para entender o armazenamento do Mac e revisar a migração seletiva de caches para um SSD externo. A base nasceu como CacheSSD. Esta é uma versão local inicial, sem notarização pública.

[English](README.md) · [Estado atual](docs/context/CURRENT_STATE.md) · [Roadmap vivo](docs/ROADMAP.md) · [Plano histórico](docs/plans/PLANO-V1-APROVADO.md) · [Recuperação](docs/RECOVERY.md)

## Compilar e testar

Requer macOS 14 ou posterior, Xcode 16 ou posterior com Swift 6 e SDK do macOS, e Python 3. O aplicativo é compilado para Apple Silicon e tem interface em português e inglês. A compilação local usa SQLite do sistema; a opção de atualização pública usa Sparkle 2.10.1, separadamente.

~~~sh
python3 build.py
open dist/DiskWing.app
swift test -j 2
python3 -m unittest discover -s Tests/Packaging -v
~~~

A compilação usa .build/ e gera dist/DiskWing.app com assinatura local ad hoc. As opções --scratch, --configuration e --output permitem outros destinos. O script não instala o aplicativo nem altera o terminal. Duas verificações dependentes de ferramentas instaladas ficam desativadas por padrão; use DISKWING_RUN_NATIVE_TESTS=1 para executá-las em um Mac preparado.

Use python3 scripts/install_local.py dist/DiskWing.app para instalar no disco interno e manter o aplicativo disponível sem o SSD. Verificações adicionais de instalações reais usam DISKWING_RUN_INSTALL_TESTS=1 em projetos descartáveis. Veja os [testes e limites](docs/TESTING.md).

## Usar

Em **Explorar volumes**, escolha um volume e navegue pela árvore ou pelo mapa do espaço. Abrir uma pasta mantém o volume selecionado. A árvore inclui arquivos ocultos, permite busca global e continua acessível pelo teclado. Sistema e dados do Mac só são reunidos quando o grupo APFS é comprovado; cada item mantém a identidade de seu volume físico. Outros volumes montados são analisados separadamente.

Resultados parciais nunca aparecem como completos. Tamanho lógico, espaço alocado estimado e espaço livre observado são medidas diferentes. O índice SQLite carrega páginas sob demanda e mantém uma fila durável para retomar a análise, revalidando diretórios alterados. O novo explorador não tem corte fixo de profundidade, quantidade de entradas ou linhas. No Mac, o índice mantém limite de 512 MiB e reserva de 256 MiB; no SSD APFS escolhido, pode crescer com reserva de 1 GiB.

Em **Caches no SSD**, siga **Escolher SSD → Analisar caches → Revisar → Transferir e ativar → Acompanhar resultado**. A revisão reúne os aplicativos, os dados e as configurações envolvidas. Salve seu trabalho e feche os aplicativos indicados; nenhum processo é encerrado à força. Caches vazios são preparados dentro desse fluxo.

O catálogo inclui ferramentas de terminal e uma matriz gráfica com Chrome, Cursor, Xcode e Safari. A presença no catálogo não comprova compatibilidade: cada integração exige qualificação própria da versão, do cache normalmente usado e do funcionamento sem SSD. As exceções continuam locais e aparecem com motivo. Consulte o [estado e as evidências atuais](docs/context/CURRENT_STATE.md). Não há redirecionamento geral de `Library/Caches`. Perfis, contas, cookies, senhas, projetos, SDKs, instalações e executáveis locais do npx ficam preservados.

A interface diferencia nenhum cache transferido, configuração pendente de uso, uso do SSD comprovado, temporário sem SSD e erros. Só selecionar o SSD ou marcar uma integração não transfere dados. Uma cópia que mantém a origem não conta como espaço liberado. O original de um cache gráfico é preservado até comprovar o uso do destino pelo aplicativo.

As ferramentas de terminal exigem atualização revisada da integração e um novo terminal. Aplicativos gráficos usam apenas seu próprio mecanismo qualificado e não dependem de um executor especial. Sem SSD, continuam pelo retorno documentado da integração; o Chrome pode usar rede e memória enquanto o cache persistente não estiver disponível. A volta ao SSD pode exigir reabertura. Cópias e gerações temporárias ficam preservadas; bancos arbitrários não são mesclados.

A Lixeira permite revisar arquivos pessoais elegíveis em qualquer volume qualificado, inclusive caches não gerenciados. Raízes, sistema, dados sensíveis, instalações protegidas, caches gerenciados e recuperação permanecem protegidos. Volume, montagem e identidade são conferidos novamente na confirmação. Se a Lixeira do sistema de arquivos não estiver qualificada ou falhar, a ação é recusada, sem exclusão permanente alternativa. A recuperação usa a identidade do volume após remontagem e nunca sobrescreve um novo arquivo.

O espaço só é recuperado após você revisar e esvaziar a Lixeira no Finder. O DiskWing não a esvazia e não faz limpeza automática. Use **Preparar para ejetar** e aguarde o macOS antes de desconectar. Processos abertos podem impedir a ejeção; retirar o cabo durante uma operação continua sendo um risco não qualificado.

A análise é local e não percorre links nem baixa conteúdo da nuvem intencionalmente. Relatórios exportados contêm caminhos e devem ser revisados antes de compartilhar. Blocos compartilhados e snapshots do APFS impedem prometer espaço recuperável apenas pela soma dos arquivos. O acompanhamento antigo de pastas e seus alertas continuam opcionais.

## Continuar o desenvolvimento

Leia [AGENTS.md](AGENTS.md), o [contexto consolidado](docs/context/PROJECT_CONTEXT.md), as [limitações e testes](docs/TESTING.md) e as [instruções de contribuição](CONTRIBUTING.md). A marca aprovada é Lift; seus arquivos editáveis e recursos macOS estão em design/brand/.

Os nomes internos CacheSSD e os formatos persistidos foram mantidos para preservar configurações. A migração do repositório não ativa migrações de caches pessoais. Licença MIT, com a fonte Manrope sob a licença OFL incluída.

A versão pública depende de assinatura Developer ID, notarização, validação em outro Mac e beta com cinco usuários gerais e cinco desenvolvedores durante sete dias. A implementação dessas estruturas não comprova essas etapas. Consulte [distribuição](docs/DISTRIBUTION.md) e [protocolo da beta](docs/beta/PROTOCOL.md).

O destino das cópias e migrações precisa preservar permissões e metadados. APFS foi validado localmente; exFAT é recusado. A conferência exige ao menos 256 MiB livres e pode interromper a operação preservando a origem. Veja a [validação dos sistemas de arquivos](docs/validation/FILESYSTEMS-2026-11-10.md).

O [kit de validação](docs/acceptance/SECOND_MAC.md) executa amostras isoladas a partir do aplicativo e prepara a revisão em outro Mac. Seus resultados não substituem os testes com pessoas.
