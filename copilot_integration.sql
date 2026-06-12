-- ============================================================================
-- CREATING A MICROSOFT COPILOT STUDIO AGENT FOR SNOWFLAKE CORTEX
-- Step-by-Step Integration Guide
-- ============================================================================

-- ============================================================================
-- PREREQUISITES
-- ============================================================================
-- 1. Snowflake: ACCOUNTADMIN or SECURITYADMIN role
-- 2. Microsoft: Global Administrator for your Entra ID tenant
-- 3. A working Cortex Agent in your Snowflake account (or Snowflake Intelligence agent)
-- 4. Microsoft Teams licenses (+ Copilot license for M365 Copilot use)
-- 5. Microsoft Tenant ID (find in Azure Portal > Entra ID > Overview)


-- ============================================================================
-- STEP 1: GRANT ENTRA ID TENANT-WIDE CONSENT (Azure Admin Action)
-- ============================================================================
-- This step is performed in a web browser by a Microsoft Global Administrator.
--
-- 1a. Grant consent for OAuth Resource:
--     Navigate to:
--     https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=5a840489-78db-4a42-8772-47be9d833efe
--     Click "Accept" on the permissions dialog.
--
-- 1b. Grant consent for OAuth Client:
--     Navigate to:
--     https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=bfdfa2a2-bce5-4aee-ad3d-41ef70eb5086
--     Click "Accept" on BOTH permission dialogs (2 of 2).
--
-- 1c. Verify in Entra Admin Center:
--     Go to Enterprise Applications > search "Snowflake Cortex Agent"
--     Confirm both apps appear:
--       - Snowflake Cortex Agents Bot OAuth Resource
--       - Snowflake Cortex Agents Bot OAuth Client
--
-- NOTE: You may see a "Missing required query string parameter: code" error.
--       This can be safely ignored - consent was still granted successfully.


-- ============================================================================
-- STEP 2: CREATE SNOWFLAKE SECURITY INTEGRATION
-- ============================================================================
-- Run as ACCOUNTADMIN. Replace <tenant-id> with your Microsoft Tenant ID.

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECURITY INTEGRATION entra_id_cortex_agents_integration
    TYPE = EXTERNAL_OAUTH
    ENABLED = TRUE
    EXTERNAL_OAUTH_TYPE = AZURE
    EXTERNAL_OAUTH_ISSUER = 'https://login.microsoftonline.com/<tenant-id>/v2.0'
    EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys'
    EXTERNAL_OAUTH_AUDIENCE_LIST = ('5a840489-78db-4a42-8772-47be9d833efe')
    EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = ('email', 'upn')
    EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'email_address'
    EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE';

-- Verify the integration was created:
DESCRIBE SECURITY INTEGRATION entra_id_cortex_agents_integration;


-- ============================================================================
-- STEP 3: ENSURE USER MAPPING (Entra ID <-> Snowflake)
-- ============================================================================
-- Each Entra ID user must map 1:1 to a Snowflake user.
-- The Snowflake user EMAIL_ADDRESS must match their Entra ID email exactly.

-- Set email for each user who will use the integration:
ALTER USER <username> SET EMAIL = '<user@company.com>';

-- Verify user mapping:
DESCRIBE USER <username>;
-- Check the EMAIL_ADDRESS property matches the Entra ID email.

-- For multiple users, repeat:
-- ALTER USER user1 SET EMAIL = 'user1@company.com';
-- ALTER USER user2 SET EMAIL = 'user2@company.com';


-- ============================================================================
-- STEP 4: CREATE OR CONFIGURE A CORTEX AGENT
-- ============================================================================
-- Option A: Use an existing Snowflake Intelligence agent (no action needed).
--
-- Option B: Create a new Cortex Agent via Snowsight UI:
--   1. Navigate to AI & ML > Agents
--   2. Click "Create Agent"
--   3. Configure tools (Cortex Search, Cortex Analyst, etc.)
--   4. Set instructions for the agent
--   5. Save and test
--
-- Option C: Create via SQL/API (refer to Cortex Agents documentation)
--
-- NOTE: Any changes to an agent in Snowflake Intelligence are immediately
--       reflected in Teams and M365 Copilot - no reconfiguration needed.


-- ============================================================================
-- STEP 5: GRANT REQUIRED PRIVILEGES TO USERS
-- ============================================================================
-- The user's default role must have access to the agent and its objects.

-- Option A: Set a role with proper access as the user's default role:
GRANT ROLE <agent_access_role> TO USER <username>;
ALTER USER <username> SET DEFAULT_ROLE = '<agent_access_role>';

-- Option B: Use secondary roles (doesn't change the user's primary role):
GRANT ROLE <agent_access_role> TO USER <username>;
ALTER USER <username> SET DEFAULT_SECONDARY_ROLES = ('ALL');

-- Required privileges for the role:
-- - USAGE on the database and schema containing the agent
-- - USAGE on the warehouse
-- - USAGE on the agent object
-- - SELECT on underlying tables/views used by the agent
-- - USAGE on any Cortex Search services referenced by the agent

-- IMPORTANT: Administrative roles (ACCOUNTADMIN, SECURITYADMIN, etc.) are
-- blocked by default in security integrations. Do NOT use them as default roles.


-- ============================================================================
-- STEP 6: INSTALL THE TEAMS APP (End User / Teams Admin Action)
-- ============================================================================
-- 1. Open Microsoft Teams
-- 2. Go to the Apps store (left sidebar)
-- 3. Search for "Snowflake Cortex Agents"
-- 4. Click "Add" to install the app
--
-- NOTE: Depending on your organization's Teams policies, a Teams Administrator
--       may need to approve the app before it is available to users.
--       See: Teams Admin Center > Manage Apps


-- ============================================================================
-- STEP 7: CONNECT SNOWFLAKE ACCOUNT TO THE BOT (First-Time Admin Setup)
-- ============================================================================
-- This is done ONCE by a Snowflake admin user in Teams:
--
-- 1. Open the "Snowflake Cortex Agents" bot in Teams
-- 2. Click "I'm the Snowflake administrator"
-- 3. Enter your Snowflake account URL:
--    Format: your-org-your-account.snowflakecomputing.com
--    (Find in Snowsight: click account selector in bottom-left corner)
-- 4. Complete the validation wizard
-- 5. If your account is NOT in Azure US East 2, accept the data processing consent
--
-- To add additional Snowflake accounts later:
--   Type "add account" in the bot chat
--
-- IMPORTANT: The admin user's default role must NOT be an administrative role
-- (ACCOUNTADMIN, etc.). Create a dedicated non-admin role with required permissions.


-- ============================================================================
-- STEP 8: USE IN MICROSOFT 365 COPILOT
-- ============================================================================
-- Once connected, the agent is available in two interfaces:
--
-- A. TEAMS BOT (dedicated chat):
--    - Open the Snowflake Cortex Agents app in Teams
--    - Ask natural language questions about your data
--    - Switch agents: type "Choose agent"
--    - Clear context: type "Clear context"
--    - View help: type "Help"
--
-- B. M365 COPILOT AGENT (within Copilot ecosystem):
--    - Requires a Microsoft 365 Copilot license
--    - The agent appears in the Copilot interface
--    - Ask questions about Snowflake data within your broader workflow
--
-- Available bot commands:
--   Help                    - List available commands
--   Choose agent            - Switch between available Cortex Agents
--   Logout                  - Log out from current account
--   Show configured accounts - List all configured Snowflake accounts
--   Clear context           - Clear agent chat history
--   Starter prompts         - See example questions
--   Admin Panel             - Admin commands
--   Add account             - Connect additional Snowflake account
--   Remove account          - Disconnect a Snowflake account


-- ============================================================================
-- KEY NOTES AND LIMITATIONS
-- ============================================================================
-- - Private Link is NOT supported (must be disabled)
-- - The bot fully respects Snowflake RBAC, masking policies, and row-level security
-- - User data never leaves Snowflake's governance boundary
-- - Only user prompts are sent to the Cortex Agents API
-- - SQL queries execute within YOUR Snowflake virtual warehouse
-- - Network policies are respected (IP from Microsoft token is forwarded)
-- - Sovereign cloud regions are NOT supported
-- - OAuth identity provider must be Microsoft Entra ID
-- - Feedback on answers is available in Teams only (not M365 Copilot)


-- ============================================================================
-- TROUBLESHOOTING
-- ============================================================================

-- Error: "Invalid OAuth access token" (390303)
-- Fix: Verify tenant-id in EXTERNAL_OAUTH_ISSUER and JWS_KEYS_URL
DESCRIBE SECURITY INTEGRATION entra_id_cortex_agents_integration;

-- Error: "Incorrect username or password" (390304)
-- Fix: User email mapping mismatch. Check:
DESCRIBE USER <username>;
-- Ensure EMAIL_ADDRESS matches Entra ID email exactly

-- Error: "Role not listed in access token" (390317)
-- Fix: Enable any-role mode:
ALTER SECURITY INTEGRATION entra_id_cortex_agents_integration
    SET EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE';

-- Error: "Role specified in connect string not granted" (390186)
-- Fix: Check blocked roles list and ensure user's default role is not blocked:
DESCRIBE SECURITY INTEGRATION entra_id_cortex_agents_integration;
-- Verify EXTERNAL_OAUTH_BLOCKED_ROLES_LIST does not contain the user's default role

-- Network policy blocking users:
-- 1. Verify user can log into Snowsight directly (confirms IP is allowlisted)
-- 2. Have user type /logout then /login in Teams to refresh the token
-- 3. IPv6 addresses are not currently supported in network policies
