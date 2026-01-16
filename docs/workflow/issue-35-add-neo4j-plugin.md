# Workflow: Neo4j Plugin Implementation

**Issue**: #35 - Add Neo4j plugin for GraphRAG development environment

## Implementation Phases

### Phase 1: Core Plugin Structure

1. Create `templates/neo4j/` directory structure
2. Implement `plugin.sh` with required functions:
   - `plugin_name()` - Return "neo4j"
   - `plugin_description()` - Return description
   - `plugin_post_copy()` - Handle configuration merging

### Phase 2: Docker Configuration

3. Create `docker/docker-compose.neo4j.yml`:
   - Neo4j Community image
   - APOC plugin configuration
   - Port mappings (7474, 7687)
   - Volume for data persistence
   - Healthcheck configuration

### Phase 3: Development Environment

4. Create `.devcontainer/devcontainer.json`:
   - Cypher language extension
5. Create `.env.example`:
   - NEO4J_USER
   - NEO4J_PASSWORD

### Phase 4: Initialization Support

6. Create `init/.gitkeep`:
   - Import directory for initialization scripts

### Phase 5: Testing

7. Run shellcheck on plugin.sh
8. Verify plugin structure matches PostgreSQL pattern
9. Run E2E tests if available

## Task Checklist

- [ ] Create directory structure
- [ ] Implement plugin.sh
- [ ] Create docker-compose.neo4j.yml
- [ ] Create devcontainer.json
- [ ] Create .env.example
- [ ] Create init/.gitkeep
- [ ] Run shellcheck
- [ ] Verify integration

## Dependencies

- Existing merge utilities in `scripts/lib/common.sh`:
  - `merge_docker_compose_services()`
  - `merge_devcontainer_json()`

## Rollback

If issues arise, simply remove `templates/neo4j/` directory.
