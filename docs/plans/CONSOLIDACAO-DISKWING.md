> Plano de consolidação aprovado em 2026-11-09. Versão pública sanitizada; o estado efetivo está em ../context/MIGRATION-2026-11-09.md.

# Consolidar o DiskWing como projeto open source

## Resultado esperado

Usar exclusivamente o repositório [Gabriellimmaa/DiskWing](https://github.com/Gabriellimmaa/DiskWing), já clonado em `<checkout do DiskWing>`, para continuar o desenvolvimento.

Levar código, testes, planos, identidade visual e contexto consolidado para ele. Adotar licença MIT e retirar a pasta antiga somente após verificar a transferência. O projeto separado do ChatGPT será preservado.

## 1. Transferir e conferir o material

- Inventariar a implementação final CacheSSD 0.1.0, os pacotes entregues, os planos, as evidências e os arquivos de marca.
- Usar como base a implementação final no SSD, conferindo-a contra o pacote de fontes entregue.
- Colocar `Package.swift`, `Sources`, `Tests` e os recursos necessários diretamente na estrutura do repositório.
- Organizar documentação em `docs/` e a identidade Lift aprovada em `design/`, preservando também os conceitos anteriores como estudos históricos.
- Guardar versões intermediárias, pacotes antigos e evidências pessoais em `.local/migration/2026-11-09/`, dentro do checkout, com acesso restrito e exclusão do Git.
- Criar um inventário com origem, destino e hashes. Qualquer arquivo indisponível por causa do iCloud impede a remoção da origem até ser recuperado e conferido.

## 2. Preparar a base pública

- Criar README principal em inglês e versão em português, com apresentação, requisitos, compilação, testes, limitações e recuperação.
- Adicionar licença MIT, atribuição da fonte Manrope com sua licença OFL, orientações de contribuição, política de segurança, changelog e modelos de issues e pull requests.
- Usar DiskWing na apresentação, documentação e nome visível do aplicativo; aplicar o ícone Lift aprovado no empacotamento.
- Preservar nesta etapa os identificadores internos, formatos de configuração, diretórios de dados e marcadores da integração CacheSSD. Documentar essa compatibilidade para evitar perda de configurações.
- Tornar a compilação independente deste Mac: remover caminhos pessoais e a exigência do PortableSSD, manter as opções existentes de configuração e destino, usar `.build/` e `dist/` como padrões e compilar diretamente do checkout.
- Declarar as dependências das ferramentas de geração da marca, eliminando referências aos recursos internos do Codex.
- Excluir do Git arquivos pessoais, conversas completas, registros brutos, caches, compilações, certificados e pacotes antigos.
- Configurar CI no macOS para compilar e executar testes isolados. As verificações que dependem de ferramentas instaladas terão execução explícita e separada.

## 3. Preservar contexto e organizar o Codex

- Criar `AGENTS.md` como ponto de entrada, indicando arquitetura, comandos, documentos de referência e regras de preservação de dados.
- Consolidar em `docs/context/` as decisões aprovadas, evolução do produto, escolha do nome e da marca, estado atual, limitações e próximos passos.
- Preservar o plano v1 e o relatório original no arquivo privado; publicar versões identificadas como sanitizadas, mantendo seu conteúdo técnico e histórico.
- Manter as conversas originais no Codex e arquivar localmente suas mensagens visíveis relevantes. Não publicar configurações pessoais nem memórias de outros projetos.
- Registrar uma nota na memória do Codex apontando para o novo repositório e seus documentos oficiais.
- Associar “Mover caches do Mac para SSD” e “Sugerir nomes para app macOS” ao mesmo projeto local.
- Renomear a entrada local existente para DiskWing, preservando o histórico. Ela já aponta para o repositório correto; não será apagada e recriada.
- A renomeação será feita pelo controle oficial de edição do projeto. Se esse controle não estiver acessível pelas ferramentas, esse único ajuste será indicado para conclusão na interface, sem editar os arquivos internos do Codex.

## 4. Validar, publicar e retirar a pasta antiga

- Conferir todos os arquivos transferidos e suas licenças.
- Executar a suíte existente de 26 testes, acrescentando verificações de portabilidade quando necessário; registrar separadamente testes ignorados e verificações nativas.
- Compilar o aplicativo em produção, conferir a assinatura local e confirmar que o pacote usa a identidade DiskWing.
- Revisar o conteúdo que será publicado para eliminar caminhos pessoais, identificadores de discos e dados privados.
- Criar o primeiro commit sanitizado, enviar para `main` e conferir o resultado da CI.
- Confirmar que o contexto necessário para continuar o desenvolvimento está documentado no repositório.
- Só então enviar a pasta antiga `MACOS - Cleaner` à Lixeira, mantendo a recuperação disponível.

Esta etapa não ativará migrações de caches, não alterará o Chrome e não publicará uma release do aplicativo. A entrega será a base organizada e publicada no GitHub, pronta para continuar o desenvolvimento.
