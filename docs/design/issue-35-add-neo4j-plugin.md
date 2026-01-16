# Design Document: Neo4j Plugin for GraphRAG

**Issue**: #35 - Add Neo4j plugin for GraphRAG development environment

## Overview

Add a Neo4j graph database plugin to enable GraphRAG (Graph Retrieval-Augmented Generation) development workflows. The plugin follows the existing PostgreSQL plugin architecture pattern.

## Architecture

### Plugin Structure

```
templates/neo4j/
├── plugin.sh                      # Plugin definition
├── docker/
│   └── docker-compose.neo4j.yml   # Neo4j service definition
├── .devcontainer/
│   └── devcontainer.json          # VS Code extensions
├── .env.example                   # Environment variables template
└── init/
    └── .gitkeep                   # Import directory for initialization
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    setup.sh                             │
│  ┌─────────────────────────────────────────────────────┤
│  │ plugin_post_copy()                                  │
│  │  ├─ Merge docker-compose.yml with Neo4j service    │
│  │  ├─ Merge devcontainer.json with VS Code extensions│
│  │  ├─ Generate .env.example / .env                   │
│  │  └─ Copy init/ directory                           │
│  └─────────────────────────────────────────────────────┤
└─────────────────────────────────────────────────────────┘
```

## Technical Specifications

### Neo4j Service Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| Image | `neo4j:community` | Latest Community edition |
| HTTP Port | 7474 | Neo4j Browser access |
| Bolt Port | 7687 | Driver connections |
| Plugin | APOC | Utility procedures for GraphRAG |
| Volume | `neo4j_data` | Data persistence |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEO4J_USER` | `neo4j` | Database username |
| `NEO4J_PASSWORD` | `password` | Database password |

### VS Code Extensions

- `jakebathman.cypher-query-language` - Cypher syntax highlighting

## Integration Points

### LangChain

```python
from langchain_community.graphs import Neo4jGraph

graph = Neo4jGraph(
    url="bolt://localhost:7687",
    username="neo4j",
    password="password"
)
```

### LlamaIndex

```python
from llama_index.graph_stores.neo4j import Neo4jPropertyGraphStore

graph_store = Neo4jPropertyGraphStore(
    username="neo4j",
    password="password",
    url="bolt://localhost:7687",
)
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Edition | Community | Sufficient for dev; no license required |
| Plugin | APOC only | Essential for GraphRAG; GDS can be added later |
| Init method | Import directory | Neo4j standard approach (differs from PostgreSQL) |
| Healthcheck | cypher-shell | Native Neo4j health verification |

## References

- PostgreSQL plugin: `templates/postgresql/`
- Plugin architecture: `docs/design/plugin-architecture.md`
- Neo4j Docker: https://hub.docker.com/_/neo4j
