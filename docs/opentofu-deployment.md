# Deploy with OpenTofu

> **Status:** The integration is implemented in the open pull request
> [`egovhealthcare/gcp_template#28`](https://github.com/egovhealthcare/gcp_template/pull/28).
> This repository supplies the SQL; `gcp_template` owns the OpenTofu, Secret,
> Helm, and Kubernetes Job resources.

The implementation details below were checked against PR head
`d127994a0d389136ffa78c0da0f0686354ba23cb`. Recheck this guide if the pull
request changes.

## What OpenTofu Applies

OpenTofu does not execute `psql` on the operator's machine. Applying the
`gcp_template/deploy` stack updates the Metabase Helm release. A Helm
post-install/post-upgrade/post-rollback hook then runs a Kubernetes Job inside
GKE.

```text
gcp_template tfvars
       |
       v
OpenTofu KMS stack
  creates three random role passwords
       |
       v
OpenTofu deploy stack
  resolves the requested metabase_etl Git ref
  creates metabase-etl-secret
  updates the Metabase Helm release
       |
       v
Helm hook Job in GKE
  init container clones metabase_etl
  provision container runs sql/00 through sql/06 with psql
       |
       +--> CARE source primary
       +--> metabase_warehouse
       `--> warehouse postgres database for pg_cron
```

The SQL files remain authoritative for database objects. OpenTofu does not
template their contents or manage the same PostgreSQL roles, grants, schemas,
FDW objects, and cron jobs through a PostgreSQL provider.

## Validated Implementation Context

| Item | Implementation in `gcp_template#28` |
|---|---|
| Runtime | OpenTofu `~> 1.11` |
| Providers | Google/Google Beta `~> 6.33`, Kubernetes `~> 2.0`, Helm `~> 2.0`, Random `~> 3.7`, HTTP `~> 3.0` |
| State | GCS backends; `deploy` reads the `infra` and `keys` remote states |
| Execution | Apply `KMS`, `infra`, then `deploy` in that order |
| Network | GKE must reach the CARE primary, source read replica, and warehouse over private networking |
| Repository access | The Job clones over unauthenticated HTTPS; the SQL repository and selected ref must be publicly readable |
| Environment | Treat as production-critical and require a reviewed saved plan before apply |

The warehouse Cloud SQL instance must already have
`cloudsql.enable_pg_cron=on`. Enabling the flag can restart the instance and is
outside this SQL repository.

## Configure the ETL Source

Set these values in the target environment tfvars in `gcp_template`:

```hcl
metabase_etl_repo   = "egovhealthcare/metabase_etl"
metabase_etl_branch = "<reviewed-commit-sha>"
```

`metabase_etl_repo` enables provisioning when non-null. It must use
`owner/repo` format.

`metabase_etl_branch` accepts a branch, tag, or commit SHA. Use an immutable
commit SHA for production so the reviewed SQL is the SQL that the Job fetches.
A mutable branch makes each plan resolve its latest GitHub commit and can
retrigger provisioning when that branch advances.

The implementation calls the unauthenticated GitHub commits API during
plan/apply. Private repositories and API-rate-limited environments require an
authenticated fetch design that is not present in the pull request.

## How a SQL Change Triggers the Job

When `metabase_etl_repo` is enabled:

1. The HTTP provider resolves `metabase_etl_branch` to its current commit SHA.
2. OpenTofu passes that SHA into the Metabase Helm values.
3. The Job template stores it in the `checksum/etl-commit` annotation.
4. A changed checksum updates the Helm release.
5. The post-upgrade hook deletes the previous hook Job before creating a new
   one.
6. The init container fetches the selected ref and copies `sql/00` through
   `sql/06` into an `emptyDir` volume.
7. The provision container executes all seven files in numeric order.

The init container uses the fixed glob `sql/0[0-6]-*.sql`. Adding `sql/07` or
later requires a coordinated change to the provision Job in
`egovhealthcare/gcp_template`; a new file outside that glob is not executed.

The Job has `backoffLimit: 2` and is retained for 12 hours after completion.
The hook also runs after a Helm rollback, so a rollback can reapply SQL.
Every hook run also drops and recreates the `care_read_replica` foreign server
and the complete `replica` schema. Use the
[documented pause and resume commands](operations.md#pause-and-resume-schedules)
before applying a Metabase Helm change, including a change unrelated to this
SQL repository.

## How Variables Reach the SQL

OpenTofu creates the Kubernetes Secret `metabase-etl-secret`. The Job imports
all of its keys with `envFrom`. Its shell function then passes those values to
every `psql` invocation:

```sh
psql "$connstr" \
  -v WAREHOUSE_ETL_PASSWORD="$WAREHOUSE_ETL_PASSWORD" \
  -v FDW_READER_PASSWORD="$FDW_READER_PASSWORD" \
  -v METABASE_READER_PASSWORD="$METABASE_READER_PASSWORD" \
  -v SOURCE_REPLICA_HOST="$SOURCE_REPLICA_HOST" \
  -v SOURCE_DBNAME="$SOURCE_DBNAME" \
  -v WAREHOUSE_DB="$WAREHOUSE_DB" \
  -v ON_ERROR_STOP=1 \
  -f "/sql/$file"
```

The scripts use native `psql` quoting:

- `:'NAME'` escapes a value as an SQL string literal.
- `:NAME` inserts a trusted SQL identifier.

OpenTofu and Helm never rewrite SQL with `templatefile()`, `envsubst`, or shell
replacement. See [Deployment variables](variables.md) for every source and
destination.

## Database Targets and Order

| Step | Connection secret | Target | Purpose |
|---:|---|---|---|
| `00` | `CARE_SOURCE_URL` | CARE source primary / `${app}_${environment}` | Create the FDW reader |
| `01` | `WAREHOUSE_URL` | Warehouse / `metabase_warehouse` | Create schemas, roles, and FDW server |
| `02` | `WAREHOUSE_URL` | Warehouse / `metabase_warehouse` | Import foreign tables |
| `03` | `WAREHOUSE_URL` | Warehouse / `metabase_warehouse` | Create ETL state and functions |
| `04` | `WAREHOUSE_URL` | Warehouse / `metabase_warehouse` | Register tables |
| `05` | `POSTGRES_URL` | Warehouse / `postgres` | Create `pg_cron` jobs targeting the warehouse |
| `06` | `WAREHOUSE_URL` | Warehouse / `metabase_warehouse` | Create the Metabase reader |

The Job combines `psql -v ON_ERROR_STOP=1` with `set -euo pipefail`.
`ON_ERROR_STOP` makes `psql` stop the current file and return a non-zero status;
`set -e` then terminates the Job's shell before the next file starts. Step `01`
drops the FDW server with `CASCADE`; step `02` restores the imported foreign
tables when step `01` succeeds.

## Plan and Apply

Apply `gcp_template` stacks in their documented order:

```text
pre-infra -> KMS -> infra -> deploy
```

The ETL password resources are created by `KMS`; the source read-replica
address is produced by `infra`; the Kubernetes Secret and Helm release are
created by `deploy`.

From each changed stack, initialize and pull the target environment variables
using the `gcp_template` Makefile. For a production apply, create a saved plan
instead of running a command that replans during apply:

```sh
make init BACKEND_BUCKET="<state-bucket>"
make pull-tfvars PROJECT_ID="<project>" ENV_NAME="<environment>"

tofu fmt -check -recursive
tofu validate
tofu plan \
  -var-file="../environments/<environment>.tfvars" \
  -out=tfplan
tofu show -no-color tfplan
```

After reviewing the plan and SQL commit, apply that exact artifact:

```sh
tofu apply tfplan
```

Before an upgrade or rollback where ETL schedules already exist, pause them
with the [operations runbook](operations.md#pause-and-resume-schedules).
Resume them only after the Job and post-apply checks succeed. A first
installation has no schedules to pause.

Do not use `-lock=false` for the reviewed production plan, and do not create a
new plan inside the apply job. Retain the plan, SQL commit SHA, OpenTofu commit
SHA, masked apply log, and resulting state versions.

## Monitor the Provisioning Job

Use the namespace configured by `gcp_template`:

```sh
export NAMESPACE="<gcp_template namespace_name>"

kubectl get jobs --namespace="$NAMESPACE" \
  -l app.kubernetes.io/component=provision

kubectl logs --namespace="$NAMESPACE" \
  -l app.kubernetes.io/component=provision \
  -c fetch-sql

kubectl logs --namespace="$NAMESPACE" \
  -l app.kubernetes.io/component=provision \
  -c provision
```

The logs should show each numbered filename and finish with `==> Done`.
Credentials must not appear in the logs.

## Post-Apply Validation

On `metabase_warehouse`:

```sql
SELECT srvname FROM pg_foreign_server;
SELECT count(*) FROM replica.facility_facility;
SELECT etl.refresh_table('facility_facility');
SELECT count(*) FROM raw.facility_facility;
SELECT * FROM etl.replication_status ORDER BY refresh_group, priority;
```

On the warehouse `postgres` database:

```sql
SELECT jobname, database, username, active
FROM cron.job
ORDER BY jobname;
```

Connect as `metabase_reader` and confirm that `raw.*` is readable and
`replica.*` is denied.

## State, Secrets, and Rollback

The implementation generates passwords with `random_password`, exports them
through the `keys` remote state, and writes them into a Kubernetes Secret from
the `deploy` stack. Consequently, role passwords and connection URLs exist in
OpenTofu state. `sensitive = true` masks output but does not remove or encrypt
state values.

Protect every GCS backend with encryption, object versioning, locking, audit
logging, and least-privilege IAM. Restrict read access to both the `keys` and
`deploy` states. Restrict Kubernetes Secret access and Job-creation privileges
in the Metabase namespace.

`tofu destroy` is not a database rollback. Deleting the Helm release or Job
does not reverse SQL that already ran. To roll back:

1. Pin `metabase_etl_branch` to a reviewed rollback commit.
2. Review the reverse SQL diff and saved OpenTofu plan.
3. Apply the exact plan artifact.
4. Monitor the hook Job.
5. Run the post-apply checks.

Take a database backup and record all relevant state versions before
destructive cleanup. Use the [recovery runbook](recovery.md) for schema and
table rebuilds or to remove the ETL from PostgreSQL completely.

## Risks and Tradeoffs

| Risk category | Current control | Remaining tradeoff |
|---|---|---|
| Secret exposure | Sensitive outputs, Kubernetes Secret, GCS backend | Passwords and connection URLs still exist in state |
| CI drift | Commit checksum retriggers Helm | Mutable refs can advance between review and fetch; pin a commit SHA |
| Provider upgrade risk | OpenTofu and provider constraints are declared | Commit `.terraform.lock.hcl` and upgrade separately |
| Blast radius | Ordered SQL and `ON_ERROR_STOP=1` | Every hook run executes all seven scripts and rebuilds the FDW server and `replica` schema |
| Testing blind spots | SQL review, Job logs, database checks | The OpenTofu plan cannot preview SQL object changes |
| Supply-chain risk | Git ref is configurable | Public unauthenticated clone and mutable container tags need hardening |
| State corruption | GCS backend and separated stack prefixes | State access exposes generated database credentials |
