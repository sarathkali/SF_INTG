CREATE OR REPLACE SECRET sf_git_secret
  TYPE = PASSWORD
  USERNAME = 'kaali'
  PASSWORD = '<secret>';

--#### 2. Create the API Integration
--This tells Snowflake that it is allowed to communicate with GitHub API endpoints.

CREATE OR REPLACE API INTEGRATION sf_git_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com')
  ALLOWED_AUTHENTICATION_SECRETS = (sf_git_secret)
  ENABLED = TRUE;


--#### 3. Create the Git Repository Stage Object
--This establishes the localized Git database stage object inside your designated schema.

CREATE OR REPLACE GIT REPOSITORY my_snowflake_project_repo
  API_INTEGRATION = sf_git_api_integration
  GIT_CREDENTIALS = sf_git_secret
  ORIGIN = 'https://github.com/sarathkali/SF_INTG.git';


--### Step 3: Configure via Snowsight UI (Alternative Method)
--If you prefer a visual interface setup, use the Snowflake web console:
1. Log in to [Snowsight](https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces-git) and select **Projects** from the left-hand menu.
2. Open your existing project or workspace workspace.
3. Click **Connect Git Repository**.
4. Choose **GitHub** as your provider.
5. Authenticate via OAuth or your newly created Personal Access Token (PAT).
6. Select your repository name and main tracking branch to link the workspace.

---

--### Step 4: Interacting with Git Files in Snowflake
--Once connected, you can pull code directly into Snowflake warehouses or write back to GitHub.

* **Fetch the latest changes:**
  ```sql
  ALTER GIT REPOSITORY my_snowflake_project_repo FETCH;
  ```
* **List tracked repository files:**
  ```sql
  LIST @my_snowflake_project_repo/branches/main/;
  ```
* **Run a SQL script directly from GitHub:**
  ```sql
  EXECUTE IMMEDIATE FROM @my_snowflake_project_repo/branches/main/scripts/deploy.sql;
  ```

---

### Recommended Folder Structure
For clean project coordination, follow this structure in your GitHub repository:
* `snowflake/` — Core folder for database schemas, tables, and views.
* `migrations/` — Deployment-ready historical data schema changes.
* `notebooks/` — [Snowflake Notebooks](https://docs.snowflake.com/en/user-guide/ui-snowsight/notebooks-snowgit) synced as `.ipynb` files.
* `procedures/` — Stored procedures and User Defined Functions (UDFs).
* `.github/workflows/` — Automated execution templates using the [Snowflake CLI GitHub Action](https://docs.snowflake.com/en/developer-guide/snowflake-cli/cicd/github-action).

If you would like, tell me:
* Whether you plan to use **dbt (data build tool)** or **Snowpark Python**.
* If you need an automated **CI/CD deployment pipeline** using GitHub Actions. 

I can customize your setup scripts and folder paths based on those details.

------------GITHUB setup - 9 June------------------------
use role accountadmin;

create or replace database GIT_POC;

--For PRIVATE REPO------------
CREATE OR REPLACE SECRET git_poc_secret
  TYPE = PASSWORD
  USERNAME = 'kaali'
  PASSWORD = '<secret>';

  show secrets;

--#### 2. Create the API Integration
--This tells Snowflake that it is allowed to communicate with GitHub API endpoints.

CREATE OR REPLACE API INTEGRATION git_poc_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com')
  ALLOWED_AUTHENTICATION_SECRETS = (git_poc_secret)
  ENABLED = TRUE;

show api integrations;
show integrations;
--#### 3. Create the Git Repository Stage Object
--This establishes the localized Git database stage object inside your designated schema.

CREATE OR REPLACE GIT REPOSITORY git_poc_snowflake_repo
  API_INTEGRATION = git_poc_api_integration
  GIT_CREDENTIALS = git_poc_secret
  ORIGIN = 'https://github.com/sarathkali/SF_INTG_PRIVATE.git';

  --For PUBLIC REPO------------

  CREATE OR REPLACE API INTEGRATION git_poc_public_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com')
  --ALLOWED_AUTHENTICATION_SECRETS = (git_poc_secret)
  ENABLED = TRUE;

  CREATE OR REPLACE GIT REPOSITORY git_poc_public_snowflake_repo
  API_INTEGRATION = git_poc_public_api_integration
  ORIGIN = 'https://github.com/sarathkali/SF_INTG.git';

  show git repositories;
  show git branches in git repository git_poc_public_snowflake_repo;
  ls @git_poc_public_snowflake_repo/branches/main;

  describe git repository git_poc_public_snowflake_repo;

  show git tags in git repository git_poc_public_snowflake_repo;
  ls @git_poc_public_snowflake_repo/tags/<tag_name>;

  ls @git_poc_public_snowflake_repo/commits/<commit_id>;

  alter git repository git_poc_public_snowflake_repo fetch;

  