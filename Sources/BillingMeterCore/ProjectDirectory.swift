import Foundation

/// Identifies projects for per-project totals (F-16).
///
/// Claude Code files each session's transcript under `~/.claude/projects/<folder>`, where the
/// folder is the directory the session was started in with every character other than a letter
/// or digit replaced by `-`. That folder is the project's identity: the last component of a
/// working directory is not unique (`Docs`, `data`, `tools` recur across unrelated repositories)
/// and changes when a session `cd`s into a subdirectory.
public enum ProjectDirectory {
    /// The folder name Claude Code uses for a session started in `path`.
    public static func folderName(for path: String) -> String {
        String(path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    /// Grouping key for a call or summary: its project folder, or, for history recorded before
    /// folders were, its display name.
    static func key(projectID: String?, project: String) -> String {
        projectID ?? "name:" + (project.isEmpty ? "(unknown)" : project)
    }

    /// A display name for each key, unique among `keys`. Normally the last path component; where
    /// two projects share it, enough parent components are added to tell them apart.
    /// `fallbackNames` names keys whose path is unknown.
    static func displayNames(keys: Set<String>, paths: [String: String],
                             fallbackNames: [String: String]) -> [String: String] {
        var components: [String: [String]] = [:]
        for key in keys {
            if let path = paths[key] {
                components[key] = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
            } else {
                components[key] = [fallbackNames[key] ?? key]
            }
        }
        var depth = Dictionary(uniqueKeysWithValues: keys.map { ($0, 1) })
        func name(_ key: String) -> String {
            let parts = components[key] ?? [key]
            return parts.suffix(depth[key] ?? 1).joined(separator: "/")
        }
        // Lengthen names shared by two or more folders until they differ or run out of components.
        // A name shared only with older, folderless history stays short; that history is labelled.
        let known = keys.filter { paths[$0] != nil }
        for _ in 0..<8 {
            let groups = Dictionary(grouping: known, by: name).filter { $0.value.count > 1 }
            if groups.isEmpty { break }
            var grew = false
            for key in groups.values.joined() where (depth[key] ?? 1) < (components[key]?.count ?? 1) {
                depth[key, default: 1] += 1
                grew = true
            }
            if !grew { break }
        }
        var result: [String: String] = [:]
        let final = Dictionary(grouping: keys, by: name)
        for key in keys {
            let n = name(key)
            // Still ambiguous: history from before folders were recorded shares a name with a folder.
            result[key] = (final[n]?.count ?? 1) > 1 && paths[key] == nil ? n + " (folder unknown)" : n
        }
        return result
    }
}
