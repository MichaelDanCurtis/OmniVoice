import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

// better-sqlite3 ships as CommonJS with `export =`; load it via createRequire so the
// import style is independent of the strict ESM tsconfig. Runtime is Node (vitest).
const require = createRequire(import.meta.url)
// eslint-disable-next-line @typescript-eslint/no-var-requires
const Database = require('better-sqlite3') as typeof import('better-sqlite3')

/// An in-memory SQLite that satisfies just enough of the D1 surface (prepare/bind/
/// first/run/all) to exercise the real SQL — including ON CONFLICT trial-stamp semantics.
export function createTestDb(): D1Database {
  const sqlite = new Database(':memory:')
  // Pass `.href` (a string) so the Node `fileURLToPath` overload is used rather than the
  // @cloudflare/workers-types global URL (which the strict typecheck otherwise flags).
  const schemaPath = fileURLToPath(new URL('../../schema.sql', import.meta.url).href)
  sqlite.exec(readFileSync(schemaPath, 'utf8'))

  const adapter = {
    prepare(sql: string) {
      const statement = sqlite.prepare(sql)
      let bound: unknown[] = []
      const api = {
        bind(...args: unknown[]) {
          bound = args
          return api
        },
        async first<T>(column?: string): Promise<T | null> {
          const row = statement.get(...bound) as Record<string, unknown> | undefined
          if (row == null) return null
          return (column ? row[column] : row) as T
        },
        async run() {
          const info = statement.run(...bound)
          return { success: true, meta: info }
        },
        async all<T>() {
          return { results: statement.all(...bound) as T[], success: true }
        },
      }
      return api
    },
  }

  return adapter as unknown as D1Database
}
