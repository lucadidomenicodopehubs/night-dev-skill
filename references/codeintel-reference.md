# CodeIntel Quick Reference for Night Dev Sub-Agents

## Available MCP Tools

When the `codeintel` MCP server is connected, these tools are available:

### list_repos
Lists all indexed repositories.
```
Input: {}
Output: [{ name: "project-name", path: "/path/to/project" }]
```

### query
Search the knowledge graph by concept.
```
Input: { query: "authentication middleware", repo: "project-name" }
Output: [{ id: "fn1", name: "validateToken", score: 0.95, ... }]
```

### context
Get full context for a symbol (callers, callees, cluster, processes).
```
Input: { name: "validateToken", repo: "project-name" }
Output: { callers: [...], callees: [...], cluster: "auth", processes: [...] }
```

### impact
Analyze blast radius of changes.
```
Input: { target: "UserService", direction: "downstream", depth: 3, repo: "project-name" }
Output: { depth1: [...], depth2: [...], depth3: [...] }
```

### detect_changes
Analyze git diff impact on knowledge graph.
```
Input: { scope: "staged", repo: "project-name" }
Output: { changedFiles: [...], affectedSymbols: [...], impactedProcesses: [...] }
```

### cypher
Execute read-only Cypher queries on the knowledge graph.
```
Input: { query: "MATCH (f:Function) RETURN f.name LIMIT 10", repo: "project-name" }
Output: [{ "f.name": "main" }, ...]
```

## Common Cypher Patterns

```cypher
-- Find all functions in a file
MATCH (f:File {path: 'src/auth.ts'})-[:DEFINES_File_Function]->(fn:Function) RETURN fn.name

-- Find call chain from a function
MATCH (a:Function {name: 'login'})-[:CALLS_Function_Function*1..3]->(b:Function) RETURN b.name, b.file_path

-- Find functions with most callers (highest blast radius)
MATCH (caller:Function)-[:CALLS_Function_Function]->(fn:Function) RETURN fn.name, COUNT(caller) AS callers ORDER BY callers DESC LIMIT 10

-- Find orphan functions (never called)
MATCH (fn:Function) WHERE NOT ()-[:CALLS_Function_Function]->(fn) RETURN fn.name, fn.file_path

-- Find circular dependencies between files
MATCH (a:File)-[:IMPORTS_File_File]->(b:File)-[:IMPORTS_File_File]->(a) RETURN a.path, b.path
```

## Night Dev Phase Mapping

| Phase | Tool | Purpose |
|-------|------|---------|
| **FASE 0 Deep Read** | `query`, `cypher` | Map entire codebase architecture, find all modules and their relationships |
| **FASE 2 Analysis Level 1** | `query` | Find code related to security/bug concerns |
| **FASE 2 Analysis Level 2** | `context` | Understand function dependencies, find test gaps |
| **FASE 2 Analysis Level 3** | `cypher`, `impact` | **Architectural critique**: find coupling hotspots, god objects, orphan code, circular deps |
| **FASE 4 Planning** | `impact` | Quantify blast radius of proposed changes, prioritize by risk |
| **FASE 5 Implementation** | `context` | Understand what you're modifying before changing it |
| **FASE 5 Architecture tasks** | `impact`, `detect_changes` | Verify architectural changes only affect expected symbols |

## Architectural Critique Cypher Queries (Level 3)

```cypher
-- Find tightly coupled functions (>10 callers) — fragile hotspots
MATCH (caller:Function)-[:CALLS_Function_Function]->(fn:Function)
WITH fn, count(caller) AS callers WHERE callers > 10
RETURN fn.name AS name, fn.file_path AS file, callers
ORDER BY callers DESC

-- Find god files (>20 defined symbols) — violate single responsibility
MATCH (f:File)-[:DEFINES_File_Function]->(fn:Function)
WITH f, count(fn) AS symbols WHERE symbols > 20
RETURN f.path AS file, symbols
ORDER BY symbols DESC

-- Find orphan clusters (<2 members) — dead or disconnected code
MATCH (fn:Function)-[:MEMBER_OF_Function_Cluster]->(c:Cluster)
WITH c, count(fn) AS members WHERE members < 2
RETURN c.name AS cluster, members

-- Find complex execution flows (>8 steps) — hard to test and debug
MATCH (p:Process) WHERE p.step_count > 8
RETURN p.name AS process, p.step_count AS steps
ORDER BY steps DESC

-- Find module cohesion: clusters with functions spread across many files
MATCH (fn:Function)-[:MEMBER_OF_Function_Cluster]->(c:Cluster)
WITH c, collect(DISTINCT fn.file_path) AS files, count(fn) AS funcs
WHERE size(files) > 3
RETURN c.name AS cluster, funcs, size(files) AS file_spread
ORDER BY file_spread DESC
```
