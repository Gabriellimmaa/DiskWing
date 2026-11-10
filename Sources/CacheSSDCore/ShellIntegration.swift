import Foundation

public enum ShellIntegration {
    private static let begin = "# >>> CacheSSD managed integration >>>"
    private static let end = "# <<< CacheSSD managed integration <<<"

    public static func install(helper: URL, store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard FileManager.default.isExecutableFile(atPath: helper.path), !helper.path.contains("\n"), !helper.path.contains("'") else { throw CacheSSDError.message("O auxiliar local não está disponível para integração.") }
        let rc = home.appendingPathComponent(".zshrc")
        let attributes = try? FileManager.default.attributesOfItem(atPath: rc.path)
        guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else { throw CacheSSDError.message("Seu arquivo .zshrc usa um link personalizado. Ele foi preservado; a integração automática não altera arquivos de dotfiles vinculados.") }
        let permissions = attributes?[.posixPermissions] ?? NSNumber(value: 0o600)
        let original = (try? String(contentsOf: rc, encoding: .utf8)) ?? ""
        let clean = removingBlock(original)
        // Preserve a byte-for-byte backup, including any pre-existing temporary-directory setting.
        try FileManager.default.createDirectory(at: store.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let backup = store.base.appendingPathComponent("zshrc-before-cachessd.txt")
        if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, atomically: true, encoding: .utf8) }
        let integration = store.base.appendingPathComponent("integration.zsh")
        guard !integration.path.contains("'") else { throw CacheSSDError.message("O caminho da integração não é compatível.") }
        let script = """
        # CacheSSD: native per-command routing; no symlinks or permanent external paths.
        if (( $+functions[_cachessd_restore] )); then _cachessd_restore; fi
        typeset -gA _cachessd_original _cachessd_was_set _cachessd_seen _cachessd_seen_set
        typeset -g _cachessd_has_seen=0
        typeset -ga _cachessd_keys
        _cachessd_keys=(npm_config_cache BUN_INSTALL_CACHE_DIR CP_CACHE_DIR PIP_CACHE_DIR HOMEBREW_CACHE GRADLE_USER_HOME UV_CACHE_DIR)
        for _cachessd_key in $_cachessd_keys; do
          _cachessd_was_set[$_cachessd_key]=${+parameters[$_cachessd_key]}
          _cachessd_original[$_cachessd_key]=${(P)_cachessd_key}
        done
        _cachessd_restore() {
          local key
          for key in $_cachessd_keys; do
            if [[ $_cachessd_has_seen == 1 ]] && { [[ ${+parameters[$key]} != $_cachessd_seen_set[$key] ]] || [[ "${(P)key}" != "$_cachessd_seen[$key]" ]]; }; then
              _cachessd_was_set[$key]=${+parameters[$key]}
              _cachessd_original[$key]=${(P)key}
            fi
            if [[ $_cachessd_was_set[$key] == 1 ]]; then
              export "$key=$_cachessd_original[$key]"
            else
              unset "$key"
            fi
          done
        }
        _cachessd_route() {
          local key value output
          local -a cachessd_route_flags
          [[ "${1-}" == *--backend* || "${1-}" == *--global-store* ]] && cachessd_route_flags+=(--omit-bun)
          [[ "${1-}" == *--link-mode* ]] && cachessd_route_flags+=(--omit-uv)
          _cachessd_restore
          [[ -x '\(helper.path)' ]] || return 0
          output=$(command '\(helper.path)' shell-env $cachessd_route_flags 2>/dev/null) || return 0
          while IFS=$'\\t' read -r key value; do
            [[ -n "$key" && -n "$value" ]] || continue
            case "$key" in
              npm_config_cache|BUN_INSTALL_CACHE_DIR|CP_CACHE_DIR|PIP_CACHE_DIR|HOMEBREW_CACHE|GRADLE_USER_HOME|UV_CACHE_DIR)
                [[ $_cachessd_was_set[$key] == 1 ]] && continue
                [[ "$key" == npm_config_cache && -n "$NPM_CONFIG_CACHE" ]] && continue
                export "$key=$value"
                ;;
            esac
          done <<< "$output"
          for key in $_cachessd_keys; do
            _cachessd_seen_set[$key]=${+parameters[$key]}
            _cachessd_seen[$key]=${(P)key}
          done
          _cachessd_has_seen=1
          return 0
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook -d preexec _cachessd_route 2>/dev/null
        add-zsh-hook preexec _cachessd_route
        _cachessd_route
        """
        try script.write(to: integration, atomically: true, encoding: .utf8)
        // Restore the macOS local temp directory only for the exact unconditional SSD line.
        // Other customized shell lines are left intact.
        let updated = clean.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let text = line.trimmingCharacters(in: .whitespaces)
            if text == "export TMPDIR=/Volumes/PortableSSD/tmp" || text == "export TMPDIR=\"/Volumes/PortableSSD/tmp\"" {
                return "# CacheSSD: local temporary directory keeps the terminal independent of the SSD.\nexport TMPDIR=\"$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)\""
            }
            return String(line)
        }.joined(separator: "\n")
        let block = "\n\(begin)\n[[ -r '\(integration.path)' ]] && source '\(integration.path)'\n\(end)\n"
        try (updated + block).write(to: rc, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: rc.path)
        var settings = store.settings(); settings.shellIntegrationEnabled = true; try store.save(settings)
        try store.append(OperationRecord(title: "Integração com o terminal ativada", detail: "Novos terminais escolhem caches por comando. Configurações personalizadas têm prioridade.", recoveryPath: backup.path))
    }

    public static func uninstall(store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let rc = home.appendingPathComponent(".zshrc")
        let attributes = try? FileManager.default.attributesOfItem(atPath: rc.path)
        guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else { throw CacheSSDError.message("O .zshrc foi substituído por um link personalizado e será preservado. Remova a integração manualmente no seu gerenciador de dotfiles.") }
        if let current = try? String(contentsOf: rc, encoding: .utf8) {
            try removingBlock(current).write(to: rc, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: attributes?[.posixPermissions] ?? NSNumber(value: 0o600)], ofItemAtPath: rc.path)
        }
        var settings = store.settings(); settings.shellIntegrationEnabled = false; settings.useExternal = false; try store.save(settings)
        try store.append(OperationRecord(title: "Integração desativada", detail: "Abra um novo terminal para usar os padrões locais. A pasta de temporários permanece local; o backup original está disponível.", recoveryPath: store.base.appendingPathComponent("zshrc-before-cachessd.txt").path))
    }

    private static func removingBlock(_ value: String) -> String {
        guard let first = value.range(of: begin), let last = value.range(of: end, range: first.upperBound..<value.endIndex) else { return value }
        var result = value; result.removeSubrange(first.lowerBound..<last.upperBound); return result
    }
}
