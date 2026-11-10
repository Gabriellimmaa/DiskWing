# Ampliação dos fluxos de caches e explorador

Escopo autorizado pelo mantenedor em 10 de novembro de 2026. Este plano atualiza o contrato vivo do produto e preserva o plano histórico aprovado. Implementação, qualificação técnica e aceitação humana são etapas distintas. A instalação do build 6 e seu backup permanecem preservados.

## Resultado esperado

1. **Caches no SSD:** transferir dados existentes elegíveis e direcionar novas gravações pelo mecanismo compatível de cada ferramenta. Também permitir preparar o SSD quando o cache local estiver vazio ou ausente. Uma cópia conferida, sozinha, não comprova direcionamento ativo.
2. **Explorador com exclusão manual:** analisar o armazenamento, navegar pelos tamanhos e revisar o envio dos itens escolhidos à Lixeira, inclusive caches e dados de aplicativos elegíveis. A exclusão manual tem uma política própria, separada da movimentação genérica.
3. **Cobertura explícita:** oferecer entrada para o volume de dados do macOS e mostrar áreas sem acesso, outros volumes e limites. A raiz do sistema protegido não representa todos os arquivos do Mac.

## Critérios de aceite

| ID | Evidência exigida |
|---|---|
| C1 | Cada integração distingue cache, configurações, perfis, credenciais, instalações e projetos. |
| C2 | Configurações explícitas do ambiente/projeto/usuário/comando prevalecem. As novas inspeções não inicializam caches pessoais. |
| C3 | Fluxos nativos descartáveis comprovam reutilização, novas gravações no SSD e retorno local. npm exige prova adicional com origem indisponível e npx preservado. |
| C4 | Origem vazia ou ausente pode preparar somente o destino externo, com registro durável e sem ativação automática do terminal. |
| C5 | A interface distingue cópia conferida, origem preservada/liberada, destino preparado e integração pendente/atualizada. |
| C6 | Liberação da origem exige prova específica, estabilidade e revisão explícita. Versões novas não herdam compatibilidade por presença no catálogo. |
| E1 | A Lixeira aceita descendentes elegíveis da pasta pessoal, inclusive caches, independentemente da política mais restrita de Mover. |
| E2 | A revisão mostra caminho, tamanho conhecido/parcial e consequências para dados de aplicativos. Arquivos na Lixeira continuam ocupando espaço. |
| E3 | Raízes, sistema, credenciais/perfis conhecidos, SDKs/ambientes vinculados, registros do DiskWing e seus ancestrais permanecem protegidos. |
| E4 | Identidade, leitura da árvore, uso por processos, cancelamento e estabilidade final são revalidados; links e placeholders não levam à leitura/exclusão do alvo. |
| E5 | A recuperação funciona nos novos caminhos de caches e recusa sobrescrever conteúdo recriado. |
| E6 | Após alterações, a análise e o inventário são atualizados ou identificados como desatualizados. |
| E7 | Os dois fluxos mantêm português/inglês, navegação por teclado e cobertura parcial honesta. |

## Ampliação de compatibilidade

O primeiro incremento acrescenta Yarn Classic e cache de compilação Go com versões exatas qualificadas, além da infraestrutura de ccache, que fica inativa até possuir sua própria qualificação. Yarn/Go preservam as origens locais nesta etapa; Bun/uv continuam preservados. A economia de espaço existente depende da elegibilidade específica, não da soma do catálogo.

Yarn moderno, stores de módulos/pacotes, SDKs, instalações, perfis Chrome e redirecionamentos amplos de caches do sistema não são incluídos implicitamente. pnpm precisa separar metadados, store e dlx. Aplicativos gráficos exigem integração própria; a integração do terminal não cobre automaticamente programas abertos pelo Dock.

Xcode é candidato a uma frente específica por oferecer local de compilação configurável, mas chaves privadas de preferências ou um teste de linha de comando não comprovam o funcionamento do aplicativo gráfico. Nenhum dado pessoal será usado para testar essa hipótese.

Fontes primárias: [Yarn Classic](https://classic.yarnpkg.com/lang/en/docs/cli/cache/), [descoberta de configuração Yarn1.22.22](https://raw.githubusercontent.com/yarnpkg/yarn/v1.22.22/src/util/rc.js), [cache Go](https://go.dev/cmd/go/), [telemetria Go](https://go.dev/doc/telemetry), [ccache](https://ccache.dev/manual/4.14.1.html), [scripts npm](https://docs.npmjs.com/cli/v10/commands/npm-run-script/#ignore-scripts) e [locais de compilação Xcode](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html).

## Organização autônoma e paralelismo

Usar toda a capacidade disponível, sem um teto organizacional para o número total de especialistas. A sessão atual oferece quatro agentes simultâneos, incluindo a coordenação. Os papéis se revezam nas vagas conforme as tarefas terminam.

Cada implementação recebe worktree na SSD, branch, arquivos exclusivos e critérios de aceite. O coordenador integra e cuida de documentação, traduções e rastreabilidade. Um autor nunca fornece a única aprovação do próprio trabalho.

| Onda | Trabalho em paralelo | Condição para avançar |
|---|---|---|
| 0 — Escopo | Pesquisa de mecanismos nativos; auditoria do explorador; revisão independente dos critérios. | Lacunas reproduzidas e tarefas registradas. |
| 1 — Implementação | Política/operação/recuperação da Lixeira; adaptadores e preparação de caches futuros; revisão independente. Coordenação integra interface e entrada do volume de dados. | Testes descartáveis pertinentes e revisão por outro autor. |
| 2 — Qualificação | Revezar especialistas em fluxos nativos, interface/acessibilidade e casos adversos de configuração/recuperação. | Evidência real separada de simulações; falhas críticas corrigidas. |
| 3 — Integração | Regressão combinada, PT/EN, pacote e revisão final. | CI do commit exato e reabertura das validações afetadas por correções. |
| 4 — Candidato e entrega | Novo artefato identificado, verificação do arquivo exato e documentação de continuidade. | Preservar instalação anterior; manter assinatura/hardware/pessoas como gates independentes. |

Leituras independentes e testes isolados podem ocorrer simultaneamente em diretórios separados. Execuções nativas, imagens de filesystem, testes de escala e integrações são serializados por uma vaga de recursos controlada pelo coordenador. Não duplicar suítes completas sem nova mudança, falha ou dúvida concreta.

Fluxo: implementar → testar → revisar independentemente → corrigir → conferir integração → PR/CI → integrar em série → verificar main. Falhas repetidas pedem diagnóstico independente, não tentativas cegas. Continuar as tarefas executáveis sem pedir aprovação para escolhas rotineiras já autorizadas.

## Preservação e continuidade

Usar homes, projetos, caches, stores, volumes e Lixeira gerados/injetados. Não migrar caches pessoais, excluir arquivos pessoais, ativar integrações reais, alterar Xcode/login ou provocar falhas físicas no SSD de desenvolvimento para testar código. Abrir o aplicativo não inicia migração nem limpeza.

Não há limpeza automática, telemetria nova ou publicação prematura. Dados desconhecidos não são descartáveis por tamanho ou nome. Tamanho lógico, blocos alocados e variação de espaço livre são medidas distintas.

Registrar requisito, responsável, arquivos, branch/base, dependências, testes, revisor, estado, SHA e próxima ação em TRACEABILITY.json. Evidências privadas e conversas ficam fora do Git. Um candidato funcional novo não herda a qualificação do arquivo anterior.

Outro Mac/macOS14, falhas físicas, aceitação humana PT/EN/VoiceOver, beta real, Developer ID/notarização e atualizações assinadas continuam pendentes até existir evidência real. Testes de agentes não substituem essas etapas.
