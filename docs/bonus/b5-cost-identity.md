# B5 - Attribute usage and estimate cost honestly

**After M3; platform track.**

## Understand

Read [token metric dimensions](https://learn.microsoft.com/en-us/azure/api-management/llm-emit-token-metric-policy)
and [Azure OpenAI pricing](https://azure.microsoft.com/en-us/pricing/details/azure-openai/).
Retail estimates are not your invoice; model deployment/SKU, token categories,
currency and price date matter.

## Build

1. Inspect actual emitted Team/API/Model/Project dimensions on your owned practice
   routes. Identify missing dimensions rather than filling them with zero.
2. Inspect the gateway's validated Entra claims. Derive a caller dimension only
   from verified identity context on **your** route; never trust a supplied team
   header or log the bearer token. Decide which non-sensitive stable identifier
   is appropriate and what cardinality it creates.
3. Compare calls made directly by your authorized participant identity with
   calls from a Foundry agent's project managed identity. The latter identifies
   the project, not necessarily the person typing in the playground.
4. If two authorized people are available, make controlled requests to the same
   practice API and verify the actual emitted distinction. One organizer using
   two agent names does not prove per-human attribution.
5. Aggregate real input/output tokens by verified model/route. Inspect the
   [dated partial price table](../../scenarios/architecture-docs/exercises/pricing.json).
   Match actual model/version/SKU and all required token-category prices.
6. Calculate estimated cost per task; separate invocation, judge and shared-service
   charges. If rates/categories are missing, report tokens/task and the missing
   inputs. Do not price all tokens with one model's output-token rate.

## Validate

- A real usage query/chart and an explained, authenticated attribution boundary.
- A reproducible estimate with date/currency/model assumptions, or an explicit
  reason money cannot yet be calculated.
- No token/body leakage, fabricated caller field or unearned per-person claim.

**Discuss:** is caller, project, team or task the most useful allocation unit?
What does APIM not measure about total lab spend?

**If stuck:** use real token counts and document the limitation. Missing prices
or a second identity are honest blockers, not zero cost or invented callers.
