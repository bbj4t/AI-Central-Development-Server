# Neon Database Integration Guide

This document explains how the Neon Database integration workflow works and how to configure it for your environment.

## Overview

The Neon workflow automatically creates and manages preview database branches for pull requests. Each PR gets its own isolated database branch that:
- Is created when a PR is opened, reopened, or synchronized
- Expires after 2 weeks
- Is automatically deleted when the PR is closed
- Can be manually triggered via workflow_dispatch

## Prerequisites

Before using the Neon integration, ensure you have:

1. **Neon Account**: Sign up at [neon.tech](https://neon.tech)
2. **Neon Project**: Create a project in your Neon dashboard
3. **GitHub Secrets**: Configure the following in your repository settings:
   - `NEON_API_KEY`: Your Neon API key (from Account Settings → API Keys)
4. **GitHub Variables**: Configure the following in your repository settings:
   - `NEON_PROJECT_ID`: Your Neon project ID (from project settings)

## Workflow Features

### 1. Automatic Branch Creation
When a PR is opened, the workflow:
- Creates a new Neon database branch named `preview/pr-{number}-{branch-name}`
- Sets an expiration date (14 days from creation)
- Posts a comment to the PR with branch details
- Outputs database URLs for use in integration steps

### 2. Database Integration
The `integrate_database` job:
- Checks out the repository
- Sets up Node.js environment
- Can run database migrations (when configured)
- Provides access to database URLs via job outputs

### 3. Schema Diff Analysis
The `schema_diff` job:
- Compares schema changes between branches
- Posts a comment to the PR with the diff
- Helps reviewers understand database impacts

### 4. Automatic Cleanup
When a PR is closed:
- The preview database branch is automatically deleted
- Resources are freed up

### 5. Manual Triggering
You can manually trigger the workflow:
1. Go to Actions → "Create/Delete Branch for Pull Request"
2. Click "Run workflow"
3. Optionally specify a PR number

## Configuration

### Setting up Database Migrations

To enable automatic database migrations, uncomment and modify the migration steps in `.github/workflows/neon_workflow.yml`:

```yaml
- name: Install dependencies
  run: npm ci
  
- name: Run Database Migrations
  run: npm run db:migrate
  env:
    DATABASE_URL: "${{ needs.create_neon_branch.outputs.db_url_with_pooler }}"
```

Ensure your project has:
- A `package.json` with a `db:migrate` script
- Migration tools configured (e.g., Prisma, Drizzle, Knex)

### Using Database URLs in Deployments

The workflow outputs are available to dependent jobs:

```yaml
- name: Deploy Preview
  env:
    DATABASE_URL: ${{ needs.create_neon_branch.outputs.db_url_with_pooler }}
  run: |
    # Your deployment commands
```

Available outputs:
- `db_url`: Direct database connection URL
- `db_url_with_pooler`: Pooled connection URL (recommended)
- `branch_id`: Neon branch identifier

## Integration with Docker Compose

To use the Neon preview database in your local or staging environment:

1. **Update your `.env` file** with the Neon connection string:
   ```bash
   DB_TYPE=postgresdb
   DB_POSTGRES_HOST=<from-neon-dashboard>
   DB_POSTGRES_PORT=5432
   DB_POSTGRES_USER=<from-neon-dashboard>
   DB_POSTGRES_PASSWORD=<from-neon-dashboard>
   DB_POSTGRESDB=<database-name>
   DB_POSTGRES_SSL=true
   ```

2. **Or use the full connection string**:
   ```bash
   NEON_DATABASE_URL=postgresql://user:pass@host.neon.tech/dbname?sslmode=require
   ```

3. **Configure n8n to use Neon**:
   Update the n8n service in `docker-compose.yml` to use Neon instead of local Postgres.

## Security Best Practices

1. **Never log database URLs**: The workflow is configured to mask credentials
2. **Use pooled connections**: Prefer `db_url_with_pooler` for better performance
3. **Rotate API keys**: Regularly rotate your Neon API key
4. **Limit permissions**: Use read-only connections where appropriate
5. **Enable SSL**: Always use SSL connections in production

## Troubleshooting

### Workflow fails to create branch
- Verify `NEON_API_KEY` is set correctly
- Verify `NEON_PROJECT_ID` matches your project
- Check Neon dashboard for project limits

### Schema diff not posting
- Ensure `permissions` are set for `pull-requests: write`
- Verify the branch name matches the pattern

### Database migrations fail
- Check that your migration tool is properly configured
- Verify database URL format is correct
- Ensure dependencies are installed before running migrations

## Example Workflow Usage

Here's a complete example of integrating Neon with a deployment workflow:

```yaml
deploy_preview:
  name: Deploy Preview Environment
  needs: create_neon_branch
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    
    - name: Setup environment
      run: |
        echo "DATABASE_URL=${{ needs.create_neon_branch.outputs.db_url_with_pooler }}" >> .env
    
    - name: Run migrations
      run: npm run db:migrate
      env:
        DATABASE_URL: ${{ needs.create_neon_branch.outputs.db_url_with_pooler }}
    
    - name: Deploy application
      run: |
        # Your deployment commands
        npm run deploy:preview
```

## Resources

- [Neon Documentation](https://neon.tech/docs)
- [Neon GitHub Actions](https://github.com/neondatabase/create-branch-action)
- [Schema Diff Action](https://github.com/neondatabase/schema-diff-action)

## Support

For issues related to:
- **Neon platform**: Contact Neon support or check their documentation
- **Workflow configuration**: Open an issue in this repository
- **Database migrations**: Check your migration tool documentation
