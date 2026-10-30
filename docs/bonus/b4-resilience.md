# B4 - Investigate resilience, safety and optional caching

**After M3; platform track.** Use only your own practice APIs/backends/policies.

## Understand

Read [APIM backends, pools and circuit breakers](https://learn.microsoft.com/en-us/azure/api-management/backends)
and [AI gateway capabilities](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities).
The two model deployments are in one account/region: this is **not regional
failover**. Request compatibility must be checked before models share a pool.

## Build

1. Inspect `gateway_exercises` in your pack: actual model backend IDs, pool,
   Content Safety and semantic-cache status. A provisioned prerequisite is not
   an enabled policy or passed acceptance test.
2. Create a prefixed practice backend/pool and route from your own API. Reuse
   existing deployments and auth. Make normal calls to each backend first,
   checking model-specific parameters and response shape.
3. Configure a circuit breaker on your practice backend. Use a controlled,
   owned failing target or a naturally observed permitted failure for the
   experiment; never disable a shared model/backend to manufacture an outage.
   Observe opening/recovery and the selected backend in actual logs.
4. Add Content Safety to your own route using the provisioned backend and
   reviewed policy reference. Test benign synthetic requests and inspect actual
   policy decisions. Do not promise that safety checks establish factual accuracy.
5. **Only if cache is already provisioned**, configure a practice semantic-cache
   policy with compatible embedding/model dimensions and safe keys. Compare
   first/repeated requests and actual backend-call evidence. Cache is off in
   the reference model policy; an existing cache alone changes no responses.
   Do not run release evaluations over cached responses.

## Validate

- An actual owned-route policy experiment and observable backend/recovery result.
- Explain the difference between resilience, content safety and caching.
- Cache evidence is either real and explicitly scoped, or marked unavailable;
  no new shared-service deployment or claim of regional recovery.

**Discuss:** what failures should trip a circuit? Which identity/authorization
context must a cache key preserve? What would invalidate a quality comparison?

**If stuck:** inspect reference backend configuration read-only and report the
specific prerequisite/policy failure. Do not modify shared policies or enable
additional infrastructure merely to finish the bonus.
