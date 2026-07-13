-- Complexity-based request routing skill for Cortex Agent with multiple Cortex Analysts
-- Co-authored with CoCo

/*
================================================================================
COMPLEXITY-BASED MODEL ROUTING FOR CORTEX AGENT
================================================================================

Architecture:
  1. CLASSIFY: A cheap model (llama3.1-8b) classifies the request as simple/medium/complex
  2. ROUTE:   Based on complexity, route to the appropriate agent tier:
              - Simple  → Agent with llama3.1-8b      (fast, low cost)
              - Medium  → Agent with llama3.1-70b     (balanced)
              - Complex → Agent with claude-3-5-sonnet (highest quality)
  3. All agents share the SAME semantic views and tools (products, inventory, suppliers)

Prerequisites:
  - Existing semantic views:
      CORTEX_ANALYST_DEMO.PUBLIC.SV_PRODUCTS
      CORTEX_ANALYST_DEMO.PUBLIC.SV_INVENTORY
      CORTEX_ANALYST_DEMO.PUBLIC.SV_SUPPLIERS
  - USAGE on database and schema
  - CREATE AGENT privilege on schema
  - SELECT on underlying tables

Billing Note:
  - Agent orchestrator is billed under SERVICE_TYPE = 'CORTEX_AGENTS' (token-based)
  - Each Cortex Analyst tool call is billed under SERVICE_TYPE = 'AI_SERVICES' (token-based)
  - Calling 3 analysts = 3x the analyst cost
  - The classification step uses llama3.1-8b which is the cheapest model (~1-2% overhead)

================================================================================
*/


-- =============================================================================
-- STEP 1: SET CONTEXT
-- =============================================================================

USE DATABASE CORTEX_ANALYST_DEMO;
USE SCHEMA PUBLIC;
USE WAREHOUSE INTELLIGENCE_WH;


-- =============================================================================
-- STEP 2: CLASSIFIER FUNCTION
-- Categorizes incoming requests as simple, medium, or complex using a cheap model
-- =============================================================================

CREATE OR REPLACE FUNCTION classify_request_complexity(user_request STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
    CASE
        WHEN LOWER(SNOWFLAKE.CORTEX.COMPLETE(
            'llama3.1-8b',
            'You are a request complexity classifier for a supply chain data system with products, inventory, and suppliers data.\n\n'
            || 'Classify the following user request into exactly one category:\n\n'
            || '**simple**: Single-domain, single-fact lookups. Examples:\n'
            || '  - "How many products do we have?"\n'
            || '  - "What is the price of Widget X?"\n'
            || '  - "List all warehouses"\n'
            || '  - "Who is supplier ABC?"\n\n'
            || '**medium**: Single-domain with filtering/aggregation, or straightforward two-domain queries. Examples:\n'
            || '  - "Show me all Electronics products priced above $100"\n'
            || '  - "Which products are below reorder level?"\n'
            || '  - "Average lead time by country"\n'
            || '  - "Total inventory value per warehouse"\n\n'
            || '**complex**: Multi-domain joins, comparisons, analytics, rankings, or questions requiring reasoning across multiple data sources. Examples:\n'
            || '  - "Which products from US suppliers have low stock across all warehouses?"\n'
            || '  - "Compare inventory turnover for Electronics vs Furniture by supplier rating"\n'
            || '  - "Identify suppliers with high ratings but frequent stockouts"\n'
            || '  - "Recommend reorder quantities based on lead times and current stock"\n\n'
            || 'Request: "' || user_request || '"\n\n'
            || 'Respond with ONLY one word: simple, medium, or complex. Nothing else.'
        )) LIKE '%complex%' THEN 'complex'
        WHEN LOWER(SNOWFLAKE.CORTEX.COMPLETE(
            'llama3.1-8b',
            'You are a request complexity classifier for a supply chain data system with products, inventory, and suppliers data.\n\n'
            || 'Classify the following user request into exactly one category:\n\n'
            || '**simple**: Single-domain, single-fact lookups. Examples:\n'
            || '  - "How many products do we have?"\n'
            || '  - "What is the price of Widget X?"\n'
            || '  - "List all warehouses"\n'
            || '  - "Who is supplier ABC?"\n\n'
            || '**medium**: Single-domain with filtering/aggregation, or straightforward two-domain queries. Examples:\n'
            || '  - "Show me all Electronics products priced above $100"\n'
            || '  - "Which products are below reorder level?"\n'
            || '  - "Average lead time by country"\n'
            || '  - "Total inventory value per warehouse"\n\n'
            || '**complex**: Multi-domain joins, comparisons, analytics, rankings, or questions requiring reasoning across multiple data sources. Examples:\n'
            || '  - "Which products from US suppliers have low stock across all warehouses?"\n'
            || '  - "Compare inventory turnover for Electronics vs Furniture by supplier rating"\n'
            || '  - "Identify suppliers with high ratings but frequent stockouts"\n'
            || '  - "Recommend reorder quantities based on lead times and current stock"\n\n'
            || 'Request: "' || user_request || '"\n\n'
            || 'Respond with ONLY one word: simple, medium, or complex. Nothing else.'
        )) LIKE '%simple%' THEN 'simple'
        ELSE 'medium'
    END
$$;


-- =============================================================================
-- STEP 3: MODEL MAPPING FUNCTION
-- Maps complexity tier to an LLM model name (for reference/logging)
-- =============================================================================

CREATE OR REPLACE FUNCTION get_model_for_complexity(complexity STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
    CASE LOWER(complexity)
        WHEN 'simple'  THEN 'llama3.1-8b'
        WHEN 'medium'  THEN 'llama3.1-70b'
        WHEN 'complex' THEN 'claude-3-5-sonnet'
        ELSE 'llama3.1-70b'
    END
$$;


-- =============================================================================
-- STEP 4: CREATE TIERED AGENTS
-- All agents share the same semantic views but differ in instruction complexity.
-- NOTE: The Cortex Agent orchestrator model is managed by Snowflake and cannot
-- be overridden in the specification. The differentiation between tiers is
-- achieved through instruction complexity and response expectations.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- SIMPLE TIER AGENT (concise instructions, minimal orchestration)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE AGENT CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_SIMPLE
  FROM SPECIFICATION $$
instructions:
  system: |
    You are a supply chain data assistant. Answer concisely.
    Route to the appropriate analyst tool based on the domain.
  orchestration: |
    ROUTING RULES:
    - Product details, pricing, categories → use "products_analyst"
    - Stock levels, warehouse locations, reorder → use "inventory_analyst"
    - Supplier info, lead times, ratings → use "suppliers_analyst"
  response: |
    Keep answers brief and in table format when showing data.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: products_analyst
      description: "Product catalog: names, categories, prices, PRODUCT_ID, SUPPLIER_ID."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: inventory_analyst
      description: "Inventory: quantity on hand, warehouse locations, reorder levels. Has PRODUCT_ID."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: suppliers_analyst
      description: "Suppliers: names, countries, lead times, ratings. Has SUPPLIER_ID."
tool_resources:
  products_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_PRODUCTS
  inventory_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_INVENTORY
  suppliers_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_SUPPLIERS
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- MEDIUM TIER AGENT (balanced instructions, cross-domain awareness)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE AGENT CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_MEDIUM
  FROM SPECIFICATION $$
instructions:
  system: |
    You are a cross-domain supply chain analyst. You help users query product,
    inventory, and supplier data. Provide clear explanations with your answers.
  orchestration: |
    ROUTING RULES:
    1. Single-domain questions - Route to the specific analyst tool:
       - Product details, pricing, categories → use "products_analyst"
       - Stock levels, warehouse locations, reorder → use "inventory_analyst"
       - Supplier info, lead times, ratings, contacts → use "suppliers_analyst"
    2. If the question could span two domains, call each relevant tool.
       Join keys: PRODUCT_ID (Products↔Inventory), SUPPLIER_ID (Products↔Suppliers)
  response: |
    Show results in a clear table format.
    For cross-domain queries, explain which data sources you combined.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: products_analyst
      description: "Product catalog: names, categories (Electronics, Furniture, Accessories), unit prices, added dates. Has PRODUCT_ID and SUPPLIER_ID."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: inventory_analyst
      description: "Inventory and stock: quantity on hand, warehouse locations (Warehouse-A/B/C), reorder levels, restock dates. Has PRODUCT_ID for joining with products."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: suppliers_analyst
      description: "Suppliers: names, contact emails, countries, delivery lead times, quality ratings. Has SUPPLIER_ID for joining with products."
tool_resources:
  products_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_PRODUCTS
  inventory_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_INVENTORY
  suppliers_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_SUPPLIERS
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- COMPLEX TIER AGENT (detailed instructions, deep analysis, step-by-step reasoning)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE AGENT CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_COMPLEX
  FROM SPECIFICATION $$
instructions:
  system: |
    You are an expert cross-domain supply chain analyst agent. You help users with
    complex analytical queries spanning product, inventory, and supplier data.
    Think step by step. Provide thorough analysis with insights.
  orchestration: |
    ROUTING RULES:
    1. Single-domain questions - Route to the specific analyst tool:
       - Product details, pricing, categories → use "products_analyst"
       - Stock levels, warehouse locations, reorder → use "inventory_analyst"
       - Supplier info, lead times, ratings, contacts → use "suppliers_analyst"

    2. Cross-domain questions - If the question spans MULTIPLE domains, call EACH
       relevant analyst tool to gather partial data, then synthesize a comprehensive answer.
       Join keys:
       - PRODUCT_ID links Products and Inventory
       - SUPPLIER_ID links Products and Suppliers

    3. For analytical questions requiring reasoning, gather all relevant data first,
       then provide insights, recommendations, and comparisons.
  response: |
    Always show results in a clear table format.
    For cross-domain queries, explain which data sources you combined.
    Provide analytical insights and actionable recommendations when appropriate.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: products_analyst
      description: "Product catalog: names, categories (Electronics, Furniture, Accessories), unit prices, added dates. Has PRODUCT_ID and SUPPLIER_ID."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: inventory_analyst
      description: "Inventory and stock: quantity on hand, warehouse locations (Warehouse-A/B/C), reorder levels, restock dates. Has PRODUCT_ID for joining with products."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: suppliers_analyst
      description: "Suppliers: names, contact emails, countries, delivery lead times, quality ratings. Has SUPPLIER_ID for joining with products."
tool_resources:
  products_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_PRODUCTS
  inventory_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_INVENTORY
  suppliers_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_SUPPLIERS
$$;


-- =============================================================================
-- STEP 5: LOGGING TABLE (for monitoring routing decisions and cost analysis)
-- =============================================================================

CREATE TABLE IF NOT EXISTS CORTEX_ANALYST_DEMO.PUBLIC.REQUEST_ROUTING_LOG (
    log_id NUMBER AUTOINCREMENT,
    request_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    user_name STRING DEFAULT CURRENT_USER(),
    user_request STRING,
    classified_complexity STRING,
    model_tier STRING,
    agent_used STRING,
    response_summary STRING
);


-- =============================================================================
-- STEP 6: MAIN ROUTING PROCEDURE (The Skill)
-- Classifies → Selects Agent → Calls Agent → Returns response with metadata
-- =============================================================================

CREATE OR REPLACE PROCEDURE route_request_to_agent(user_request STRING)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
BEGIN
    -- Step A: Classify the request complexity
    LET complexity STRING := (SELECT classify_request_complexity(:user_request));

    -- Step B: Get the model name for logging
    LET model_used STRING := (SELECT get_model_for_complexity(:complexity));

    -- Step C: Select the appropriate agent based on complexity
    LET agent_fqn STRING;
    CASE :complexity
        WHEN 'simple'  THEN agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_SIMPLE';
        WHEN 'medium'  THEN agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_MEDIUM';
        WHEN 'complex' THEN agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_COMPLEX';
        ELSE agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_MEDIUM';
    END CASE;

    -- Step D: Build request body, then call the selected agent via DATA_AGENT_RUN
    LET request_body STRING := (
        SELECT TO_JSON(OBJECT_CONSTRUCT(
            'messages', ARRAY_CONSTRUCT(
                OBJECT_CONSTRUCT(
                    'role', 'user',
                    'content', ARRAY_CONSTRUCT(
                        OBJECT_CONSTRUCT('type', 'text', 'text', :user_request)
                    )
                )
            )
        ))
    );

    LET agent_response VARIANT := (
        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(:agent_fqn, :request_body)
    );

    -- Step E: Log the routing decision
    INSERT INTO CORTEX_ANALYST_DEMO.PUBLIC.REQUEST_ROUTING_LOG
        (user_request, classified_complexity, model_tier, agent_used)
    VALUES
        (:user_request, :complexity, :model_used, :agent_fqn);

    -- Step F: Return structured response with routing metadata
    RETURN OBJECT_CONSTRUCT(
        'input_request', :user_request,
        'classified_complexity', :complexity,
        'model_tier', :model_used,
        'agent_used', :agent_fqn,
        'agent_response', :agent_response
    );
END;
$$;


-- =============================================================================
-- STEP 7: LIGHTWEIGHT ROUTING PROCEDURE (without logging)
-- Use this for production if you don't need per-request logging
-- =============================================================================

CREATE OR REPLACE PROCEDURE route_request(user_request STRING)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
BEGIN
    LET complexity STRING := (SELECT classify_request_complexity(:user_request));
    LET model_used STRING := (SELECT get_model_for_complexity(:complexity));

    LET agent_fqn STRING;
    CASE :complexity
        WHEN 'simple'  THEN agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_SIMPLE';
        WHEN 'medium'  THEN agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_MEDIUM';
        WHEN 'complex' THEN agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_COMPLEX';
        ELSE agent_fqn := 'CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_MEDIUM';
    END CASE;

    LET request_body STRING := (
        SELECT TO_JSON(OBJECT_CONSTRUCT(
            'messages', ARRAY_CONSTRUCT(
                OBJECT_CONSTRUCT(
                    'role', 'user',
                    'content', ARRAY_CONSTRUCT(
                        OBJECT_CONSTRUCT('type', 'text', 'text', :user_request)
                    )
                )
            )
        ))
    );

    LET agent_response VARIANT := (
        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(:agent_fqn, :request_body)
    );

    RETURN OBJECT_CONSTRUCT(
        'input_request', :user_request,
        'classified_complexity', :complexity,
        'model_tier', :model_used,
        'agent_used', :agent_fqn,
        'agent_response', :agent_response
    );
END;
$$;


-- =============================================================================
-- STEP 8: TEST THE CLASSIFIER
-- Run these to verify classification works correctly before testing full routing
-- =============================================================================

-- Simple requests (should classify as 'simple')
SELECT 'Test 1' AS test,
       'How many products do we have?' AS request,
       classify_request_complexity('How many products do we have?') AS complexity;

SELECT 'Test 2' AS test,
       'List all warehouses' AS request,
       classify_request_complexity('List all warehouses') AS complexity;

-- Medium requests (should classify as 'medium')
SELECT 'Test 3' AS test,
       'Show me all Electronics products priced above $100' AS request,
       classify_request_complexity('Show me all Electronics products priced above $100') AS complexity;

SELECT 'Test 4' AS test,
       'What is the average lead time by country?' AS request,
       classify_request_complexity('What is the average lead time by country?') AS complexity;

-- Complex requests (should classify as 'complex')
SELECT 'Test 5' AS test,
       'Which products from US suppliers have low stock across all warehouses?' AS request,
       classify_request_complexity('Which products from US suppliers have low stock across all warehouses?') AS complexity;

SELECT 'Test 6' AS test,
       'Analyze supplier ratings vs stockout frequency and recommend which suppliers to prioritize for reorders' AS request,
       classify_request_complexity('Analyze supplier ratings vs stockout frequency and recommend which suppliers to prioritize for reorders') AS complexity;


-- =============================================================================
-- STEP 9: TEST FULL ROUTING (end-to-end)
-- =============================================================================

-- Simple: should route to AGENT_SIMPLE (llama3.1-8b)
CALL route_request_to_agent('How many products do we have?');

-- Medium: should route to AGENT_MEDIUM (llama3.1-70b)
CALL route_request_to_agent('Show me all Electronics products priced above $100');

-- Complex: should route to AGENT_COMPLEX (claude-3-5-sonnet)
CALL route_request_to_agent('Which products from US suppliers have critically low stock across all warehouses, and which suppliers should we prioritize for reorders based on their ratings and lead times?');


-- =============================================================================
-- STEP 10: MONITOR ROUTING ANALYTICS
-- =============================================================================

-- View recent routing decisions
SELECT *
FROM CORTEX_ANALYST_DEMO.PUBLIC.REQUEST_ROUTING_LOG
ORDER BY request_timestamp DESC
LIMIT 20;

-- Routing distribution (what % of requests go to each tier?)
SELECT
    classified_complexity,
    model_tier,
    COUNT(*) AS request_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM CORTEX_ANALYST_DEMO.PUBLIC.REQUEST_ROUTING_LOG
GROUP BY classified_complexity, model_tier
ORDER BY request_count DESC;

-- Routing by user
SELECT
    user_name,
    classified_complexity,
    COUNT(*) AS requests
FROM CORTEX_ANALYST_DEMO.PUBLIC.REQUEST_ROUTING_LOG
GROUP BY user_name, classified_complexity
ORDER BY user_name, requests DESC;


-- =============================================================================
-- STEP 11: CREDIT MONITORING
-- Track actual credit usage by service type (Agent vs Analyst)
-- =============================================================================

-- Agent vs Analyst credit split (last 7 days)
SELECT
    service_type,
    SUM(credits_used) AS total_credits,
    ROUND(RATIO_TO_REPORT(SUM(credits_used)) OVER () * 100, 1) AS pct_of_total
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE service_type IN ('CORTEX_AGENTS', 'AI_SERVICES')
  AND usage_date >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY service_type
ORDER BY total_credits DESC;

-- Per-agent usage breakdown
SELECT
    START_TIME,
    AGENT_NAME,
    REQUEST_ID,
    TOKEN_CREDITS,
    TOKENS
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
WHERE AGENT_NAME LIKE 'CROSS_DOMAIN_AGENT%'
ORDER BY START_TIME DESC
LIMIT 50;


-- =============================================================================
-- STEP 12: UNIFIED SINGLE AGENT (Primary chatbot endpoint)
-- One agent that handles all complexity levels with adaptive response style
-- =============================================================================

CREATE OR REPLACE AGENT CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT
  FROM SPECIFICATION $$
instructions:
  system: |
    You are a cross-domain supply chain analyst. You answer questions about products,
    inventory, and suppliers with varying depth depending on query complexity.

    COMPLEXITY ADAPTATION:
    - Simple questions (single fact lookups like counts, single item details):
      Answer concisely in 1-2 sentences with the data.
    - Medium questions (filtering, aggregation, single-domain analysis):
      Provide a clear table and a brief summary.
    - Complex questions (multi-domain joins, comparisons, rankings, recommendations):
      Think step by step. Gather data from multiple tools, synthesize insights,
      and provide thorough analysis with recommendations.
  orchestration: |
    ROUTING RULES:
    1. Single-domain questions - Route to the specific analyst tool:
       - Product details, pricing, categories → use "products_analyst"
       - Stock levels, warehouse locations, reorder → use "inventory_analyst"
       - Supplier info, lead times, ratings, contacts → use "suppliers_analyst"

    2. Cross-domain questions - If the question spans MULTIPLE domains, call EACH
       relevant analyst tool to gather partial data, then synthesize a comprehensive answer.
       Join keys:
       - PRODUCT_ID links Products and Inventory
       - SUPPLIER_ID links Products and Suppliers

    3. For analytical questions requiring reasoning, gather all relevant data first,
       then provide insights, recommendations, and comparisons.
  response: |
    Always show results in a clear table format when data is returned.
    For cross-domain queries, explain which data sources you combined.
    Match response depth to question complexity: brief for simple, thorough for complex.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: products_analyst
      description: "Product catalog: names, categories (Electronics, Furniture, Accessories), unit prices, added dates. Has PRODUCT_ID and SUPPLIER_ID."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: inventory_analyst
      description: "Inventory and stock: quantity on hand, warehouse locations (Warehouse-A/B/C), reorder levels, restock dates. Has PRODUCT_ID for joining with products."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: suppliers_analyst
      description: "Suppliers: names, contact emails, countries, delivery lead times, quality ratings. Has SUPPLIER_ID for joining with products."
tool_resources:
  products_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_PRODUCTS
  inventory_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_INVENTORY
  suppliers_analyst:
    semantic_view: CORTEX_ANALYST_DEMO.PUBLIC.SV_SUPPLIERS
$$;


-- =============================================================================
-- STEP 13: CLEANUP (run only if you want to remove everything)
-- =============================================================================

-- DROP PROCEDURE IF EXISTS route_request_to_agent(STRING);
-- DROP PROCEDURE IF EXISTS route_request(STRING);
-- DROP FUNCTION IF EXISTS classify_request_complexity(STRING);
-- DROP FUNCTION IF EXISTS get_model_for_complexity(STRING);
-- DROP AGENT IF EXISTS CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_SIMPLE;
-- DROP AGENT IF EXISTS CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_MEDIUM;
-- DROP AGENT IF EXISTS CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT_COMPLEX;
-- DROP AGENT IF EXISTS CORTEX_ANALYST_DEMO.PUBLIC.CROSS_DOMAIN_AGENT;
-- DROP TABLE IF EXISTS CORTEX_ANALYST_DEMO.PUBLIC.REQUEST_ROUTING_LOG;