// Token-based auth middleware for AgentCockpit gateway.
// Token is read from AGENTCOCKPIT_TOKEN env var.

const GATEWAY_TOKEN = process.env.AGENTCOCKPIT_TOKEN ?? "";

if (!GATEWAY_TOKEN) {
  console.warn(
    "[auth] WARNING: AGENTCOCKPIT_TOKEN is not set. All connections will be rejected."
  );
}

/**
 * Returns true if the provided token matches the configured gateway token.
 */
export function validateToken(token: string): boolean {
  if (!GATEWAY_TOKEN) return false;
  // Constant-time comparison to avoid timing attacks
  if (token.length !== GATEWAY_TOKEN.length) return false;
  let mismatch = 0;
  for (let i = 0; i < token.length; i++) {
    mismatch |= token.charCodeAt(i) ^ GATEWAY_TOKEN.charCodeAt(i);
  }
  return mismatch === 0;
}
