# DiskWing

Aplicativo open source para entender o armazenamento do Mac e revisar a migração seletiva de caches para um SSD externo. A base nasceu como CacheSSD. Esta é uma versão local inicial, sem notarização pública.

[English](README.md) · [Estado atual](docs/context/CURRENT_STATE.md) · [Plano v1](docs/plans/PLANO-V1-APROVADO.md) · [Recuperação](docs/RECOVERY.md)

## Compilar e testar

Requer macOS 14 ou posterior, Xcode 16 ou posterior com Swift 6 e SDK do macOS, e Python 3. A interface está em português e não há dependências externas de pacotes Swift.

~~~sh
python3 build.py
open dist/DiskWing.app
swift test -j 2
python3 -m unittest discover -s Tests/Packaging -v
~~~

A compilação usa .build/ e gera dist/DiskWing.app com assinatura local ad hoc. As opções --scratch, --configuration e --output permitem outros destinos. O script não instala o aplicativo nem altera o terminal. Duas verificações dependentes de ferramentas instaladas ficam desativadas por padrão; use DISKWING_RUN_NATIVE_TESTS=1 para executá-las em um Mac preparado.

## Usar

Em **Explorar espaço**, escolha uma pasta, busque itens e navegue pelos maiores consumidores. A análise indica limitações e diferencia tamanho lógico de blocos alocados.

Em **Caches e SSD**, revise uma ferramenta por vez. A cópia é conferida antes de permitir a liberação da origem. Bun e uv mantêm as origens para preservar ambientes existentes. O Chrome, SDKs, emuladores, projetos e executáveis locais do npx ficam fora da migração.

Depois de migrar, revise a integração do terminal e abra uma nova sessão. Novos comandos usam o destino disponível; sem o SSD, voltam aos padrões locais. Aplicativos abertos pelo Dock mantêm suas próprias configurações. Use **Preparar para ejetar** antes de desconectar. Processos abertos podem impedir a ejeção, e a retirada do cabo pode interrompê-los.

Movimentações pessoais conferem uma cópia e enviam a origem à Lixeira. O espaço só é recuperado após você revisar e esvaziar a Lixeira no Finder. O DiskWing não esvazia a Lixeira nem executa limpeza automática.

A análise é local. Relatórios exportados contêm caminhos e devem ser revisados antes de compartilhar. Blocos compartilhados e snapshots do APFS impedem prometer espaço recuperável apenas pela soma dos arquivos.

## Continuar o desenvolvimento

Leia [AGENTS.md](AGENTS.md), o [contexto consolidado](docs/context/PROJECT_CONTEXT.md), as [limitações e testes](docs/TESTING.md) e as [instruções de contribuição](CONTRIBUTING.md). A marca aprovada é Lift; seus arquivos editáveis e recursos macOS estão em design/brand/.

Os nomes internos CacheSSD e os formatos persistidos foram mantidos para preservar configurações. A migração do repositório não ativa migrações de caches pessoais. Licença MIT, com a fonte Manrope sob a licença OFL incluída.
