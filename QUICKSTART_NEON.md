# Quick Start: Neon Database Integration

This guide helps you quickly set up the Neon database integration workflow.

## 1. Setup (5 minutes)

### Get Neon Credentials
1. Sign up at [neon.tech](https://neon.tech) (free tier available)
2. Create a new project or use existing one
3. Note your **Project ID** (from project settings)
4. Generate an **API Key** (Account Settings → API Keys)

### Configure GitHub Repository
1. Go to your repository Settings → Secrets and variables → Actions
2. Add **Secret**: `NEON_API_KEY` with your Neon API key
3. Add **Variable**: `NEON_PROJECT_ID` with your Neon project ID

That's it! The workflow is ready to use.

## 2. Test the Integration

### Option A: Create a Pull Request
1. Create a new branch: `git checkout -b test-neon-integration`
2. Make any change: `echo "test" > test.txt`
3. Commit and push: `git commit -am "Test" && git push`
4. Open a pull request
5. Watch the workflow run in the Actions tab
6. Check the PR for a comment with database branch details

### Option B: Manual Trigger
1. Go to Actions → "Create/Delete Branch for Pull Request"
2. Click "Run workflow"
3. Select branch and optionally specify PR number
4. Click "Run workflow" button

## 3. Use the Database Branch

After the workflow creates a branch, you'll see a comment on your PR with:
- Branch name: `preview/pr-{number}-{branch-name}`
- Branch ID
- Expiration date (14 days)

### Get Connection String
1. Go to your Neon dashboard
2. Find the preview branch in the branches list
3. Copy the connection string
4. Use it in your application or docker-compose

### Example for .env file
```bash
DATABASE_URL=postgresql://user:pass@ep-xxx.region.neon.tech/dbname?sslmode=require
```

## 4. Enable Database Migrations (Optional)

If you want automatic migrations on branch creation:

1. Add migration tooling to your project (Prisma, Drizzle, etc.)
2. Add a `db:migrate` script to `package.json`:
   ```json
   {
     "scripts": {
       "db:migrate": "prisma migrate deploy"
     }
   }
   ```
3. Uncomment migration steps in `.github/workflows/neon_workflow.yml`:
   ```yaml
   - name: Install dependencies
     run: npm ci
     
   - name: Run Database Migrations
     run: npm run db:migrate
     env:
       DATABASE_URL: "${{ needs.create_neon_branch.outputs.db_url_with_pooler }}"
   ```

## 5. Cleanup

Preview branches are automatically:
- **Created** when you open/update a PR
- **Deleted** when you close the PR
- **Expired** after 14 days

No manual cleanup needed!

## Common Use Cases

### Use Case 1: Test Database Changes
```bash
# 1. Create feature branch with schema changes
git checkout -b feature/add-users-table

# 2. Add migration files
# ... add your migration files ...

# 3. Push and create PR
git push -u origin feature/add-users-table

# 4. Workflow creates isolated DB branch
# 5. Test your changes against the preview DB
# 6. Schema diff appears in PR comments
```

### Use Case 2: Staging Environment
```bash
# 1. Deploy your app to staging with preview DB URL
# 2. Run integration tests against preview DB
# 3. Verify everything works before merging
```

### Use Case 3: Manual Database Testing
```bash
# 1. Trigger workflow manually from Actions tab
# 2. Get connection string from Neon dashboard
# 3. Connect with your favorite DB tool
# 4. Test queries, perform manual QA
```

## Troubleshooting

### Workflow not running?
- Check that `NEON_API_KEY` secret is set
- Check that `NEON_PROJECT_ID` variable is set
- Verify your Neon account is active

### Schema diff not showing?
- Ensure you have an existing main branch in Neon
- Check that permissions are set in workflow file
- Verify the branch name pattern matches

### Need help?
- Check [NEON_INTEGRATION.md](NEON_INTEGRATION.md) for detailed docs
- Review [Neon documentation](https://neon.tech/docs)
- Check workflow logs in Actions tab

## Next Steps

- ✅ Read [NEON_INTEGRATION.md](NEON_INTEGRATION.md) for comprehensive guide
- ✅ Configure database migrations for your project
- ✅ Integrate preview DBs with your deployment workflow
- ✅ Set up local development with Neon
- ✅ Review [PROJECT_PLAN.md](PROJECT_PLAN.md) for overall architecture

---

**Pro Tip**: Use pooled connections (`db_url_with_pooler`) for better performance in serverless environments!
