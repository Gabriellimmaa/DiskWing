> Versão pública sanitizada do registro original. Identificadores e evidências pessoais ficam no arquivo privado de migração. Este registro histórico não substitui o estado atual do projeto.

# Evolução do CacheSSD para gerenciar o espaço do Mac

Versão 0.1 do roadmap, definida em 8 de novembro de 2026. O plano v1 permanece como referência aprovada do módulo de caches. A implementação foi autorizada em 9 de novembro; o estado efetivo está no documento de implementação e validação.

## Direção do produto

Atender usuários de Mac em geral e desenvolvedores, com revisão antes de qualquer ação. A interface principal deve responder o que ocupa espaço, o que é esse conteúdo, quais ações são compatíveis e quanto espaço foi efetivamente recuperado.

O OmniDiskSweeper é referência para exploração: apresenta arquivos do maior para o menor e permite abri-los ou enviá-los à Lixeira. A evolução proposta combina essa exploração com explicações, operações específicas e conferência do resultado. Essa diferenciação é uma hipótese a validar. [Descrição oficial](https://www.omnigroup.com/more).

## Etapas

| Etapa | Entrega | Condição para avançar |
|---|---|---|
| Validar os fluxos | Protótipo de diagnóstico, revisão e recuperação para os dois públicos | As pessoas entendem as consequências sem orientação constante |
| Diagnóstico sem alterações | Explorador de espaço, busca, ordenação, progresso, cancelamento e Finder | Resultados consistentes e áreas não examinadas identificadas |
| Ações guiadas | Lixeira, movimentação de arquivos pessoais e operações de caches reconhecidos | Revisão, conferência e recuperação explicadas |
| Gestão de caches v1 | Direcionamento ao SSD, alternativa local, preparação para ejeção e recuperação | Testes de SSD ausente, processos ativos e interrupções aprovados |
| Acompanhamento | Histórico, comparação entre análises e identificação de crescimento | Atualizações incrementais confiáveis e consumo limitado |
| Beta para outras pessoas | Distribuição assinada, atualização, diagnóstico e suporte | Instalação e uso validados em Macs diferentes |

Duplicados, desinstalação completa e migração de bibliotecas serão priorizados conforme problemas identificados no beta. Tamanho ou idade não bastam para considerar um arquivo dispensável.

## Base técnica e confiança

Separar análise e execução. A análise coleta metadados; operações são preparadas e executadas somente depois da revisão da seleção.

Manter integrações versionadas por ferramenta, com caminhos, versões testadas, necessidade de encerramento, procedimento nativo e recuperação. Conteúdo desconhecido pode ser explorado, mas não deve receber recomendação automática de limpeza.

Diferenciar tamanho lógico, espaço alocado, estimativa recuperável e variação observada de espaço livre. Clones, hard links e snapshots podem impedir correspondência entre esses valores. [APFS](https://support.apple.com/en-ie/guide/disk-utility/dskua9e6a110/mac), [espaço alocado](https://developer.apple.com/la/documentation/foundation/urlresourcekey/fileallocatedsizekey).

Pastas inacessíveis devem aparecer como análise parcial. A varredura não deve seguir links nem baixar arquivos de nuvem para examiná-los. Acesso Total ao Disco é opcional e concedido pela pessoa nos ajustes do macOS. [Permissões](https://developer.apple.com/documentation/Security/accessing-files-from-the-macos-app-sandbox).

Índice, histórico e nomes ficam no Mac. Relatórios de suporte serão revisáveis. Atualizações futuras usarão eventos do sistema como indicação de alteração, com novas varreduras após perda de eventos. [FSEvents](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html).

A distribuição inicial será pelo site, com Developer ID, notarização, atualização assinada e desinstalação que restaure integrações locais. A Mac App Store será avaliada separadamente. [Developer ID](https://developer.apple.com/developer-id/).

## Validação do produto

O beta inicial terá cinco usuários gerais e cinco desenvolvedores. O grupo serve para descobrir problemas e ajustar o produto, sem representar validação de mercado.

Verificar compreensão dos maiores consumidores de espaço, escolha de ações sem assistência constante, recuperação de espaço imediatamente e após sete dias, falhas e interrupções, proteção de dados pessoais e custo de CPU, memória e armazenamento. Registrar diferenças entre macOS, ferramentas e formatos de disco.
