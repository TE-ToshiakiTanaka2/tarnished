# Flowchart: #276 GitHub Project auto-detection and fallback

```mermaid
graph TD
    Start[plugin_interactive_setup] --> TTY{TTY available?}
    TTY -->|No| Defaults[Apply defaults; return 0]
    TTY -->|Yes| Ref[Prompt ERD_REF]
    Ref --> CheckGh{check_gh_available?}

    CheckGh -->|No| Info1["print_info gh CLI not found,<br/>using manual configuration"]
    Info1 --> Manual

    CheckGh -->|Yes| Info2["print_info Detected gh CLI,<br/>attempting to fetch projects..."]
    Info2 --> User["get_current_user<br/>(via _gh_run)"]
    User --> UserOk{stdout non-empty?}
    UserOk -->|No| Warn1["_print_gh_warning Could not<br/>determine current user"]
    Warn1 --> Manual

    UserOk -->|Yes| Projs["get_owner_projects current_user<br/>(via _gh_run)"]
    Projs --> ProjsOk{stdout non-empty<br/>AND .projects length > 0?}
    ProjsOk -->|No: error or empty json| Warn2["_print_gh_warning Could not fetch projects<br/>OR print_warning No projects found"]
    Warn2 --> Manual

    ProjsOk -->|Yes| AutoSel[use_gh_detection = true]
    AutoSel --> Pick{count == 1?}
    Pick -->|Yes| AutoSingle[auto-select first project]
    Pick -->|No| ChooseMany[show list; read selection]
    AutoSingle --> Fields["get_project_fields_detailed<br/>(via _gh_run; falls back to<br/>get_project_fields on failure)"]
    ChooseMany --> Fields
    Fields --> FieldsOk{stdout non-empty?}
    FieldsOk -->|Yes| Detailed[categorize_fields → configure<br/>single-select / iteration / date]
    FieldsOk -->|No| Basic["get_project_fields → configure_fields_from_basic_list<br/>OR _print_gh_warning + prompt_manual_field_defaults"]
    Detailed --> LabelRouting
    Basic --> LabelRouting

    Manual[prompt_manual_project_config<br/>prompt_manual_field_defaults] --> LabelRouting
    LabelRouting{check_tty_available?} -->|Yes| LR[prompt_label_routing_setup]
    LabelRouting -->|No| Done
    LR --> Done[print_success Project configuration collected]
```

## Notes

- **Pre-fix root cause**: under `set -e`, `var=$(gh ... 2>/dev/null)`
  could abort the script when gh exited non-zero, skipping the `Manual`
  branch entirely. After this issue, every `_gh_run` returns 0, so the
  diamond `stdout non-empty?` is the sole branch point and the manual
  fallback is unconditionally reachable.
- The diamond `stdout non-empty?` at each gh helper covers four
  real-world cases:
  1. **Success** — non-empty JSON / login (proceed to next step)
  2. **Auth failure** — gh returns 1, stderr captured (empty stdout → fallback)
  3. **Network error** — same shape as auth failure (empty stdout → fallback)
  4. **No projects** — `{"projects":[]}` (non-empty stdout but `length == 0` → "No projects found" path)
- Auto-detection failure is non-fatal at every step. The user always
  reaches one of: an auto-selected project, an interactive selection
  list, or the manual prompt block.
- The remote-bootstrap stdin detach (`setup.sh:69`) is unrelated to
  this control flow but eliminates the `curl: (23)` symptom that
  appears interleaved with this flow in the user-visible output.
