# Documentation

Choose the guide that matches the task.

## Deploy

| Guide | Use it for |
|---|---|
| [OpenTofu deployment](opentofu-deployment.md) | Cross-repository OpenTofu and Helm Job deployment |
| [Variable reference](variables.md) | tfvars inputs, derived secrets, and SQL substitutions |
| [Cloud SQL Studio setup](cloud-sql-studio-setup.md) | Current manual deployment |

## Operate

| Guide | Use it for |
|---|---|
| [Operations runbook](operations.md) | Refreshes, monitoring, load control, and Metabase access |
| [Recovery runbook](recovery.md) | Failed mappings, schema drift, table rebuilds, and rollback |
| [Table catalog](table-catalog.md) | Replicated tables and their refresh modes |

## Source of Truth

- `sql/00` through `sql/06` define the database objects and must run in order.
- `sql/04-register-care-tables.sql` defines which tables are enabled and how
  they refresh.
- Documentation explains how to execute the SQL; it does not duplicate SQL
  bodies.

If documentation and SQL disagree, treat the SQL as authoritative and update
the documentation in the same change.
