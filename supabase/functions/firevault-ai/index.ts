import { createClient } from "npm:@supabase/supabase-js@2";
import { paidAccessDecision } from "../_shared/paid-access.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = request.headers.get("authorization");
    if (!authorization?.toLowerCase().startsWith("bearer ")) {
      return json({ error: "Unauthorized" }, 401);
    }
    const admin = adminClient();
    const { data: userData, error: userError } = await admin.auth.getUser(authorization.slice(7));
    if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

    const access = await paidAccessDecision(admin, userData.user.id);
    if (!access.allowed) {
      return json({ error: "Subscription Required", code: access.reason }, 402);
    }

    const openAIKey = Deno.env.get("OPENAI_API_KEY");
    if (!openAIKey) return json({ error: "OPENAI_API_KEY is not configured" }, 500);

    const body = await request.json().catch(() => ({}));
    const accountName = cleanText(body.accountName, 200) || "Unknown account";
    const technicianRequest = cleanText(body.technicianRequest, 4_000) ||
      "Provide a brief account overview.";

    const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-5.6",
        input: [
          {
            role: "system",
            content: [{
              type: "input_text",
              text: [
                "You are the FireVault Field Assistant.",
                "Be concise and practical.",
                "Do not invent equipment, problems, dates, or repairs.",
                "Clearly distinguish facts from possible patterns.",
                "Never claim a diagnosis without supporting records.",
                "Mention when insufficient information is available.",
                "Keep the response under 120 words.",
              ].join("\n"),
            }],
          },
          {
            role: "user",
            content: [{
              type: "input_text",
              text: `Account: ${accountName}\n\nTechnician request:\n${technicianRequest}\n\nNo historical account records have been provided.`,
            }],
          },
        ],
      }),
    });
    const responseData = await openAIResponse.json();
    if (!openAIResponse.ok) {
      console.error("OpenAI request failed", openAIResponse.status);
      return json({ error: "AI request failed" }, 502);
    }

    const assistantText = responseData.output
      ?.flatMap((item: { content?: unknown[] }) => item.content ?? [])
      ?.find((content: { type?: string }) => content.type === "output_text")
      ?.text ?? "No response text was returned.";
    return json({ success: true, accountName, assistantText });
  } catch (error) {
    console.error("FireVault AI error", error);
    return json({ error: "Unexpected server error" }, 500);
  }
});

function adminClient() {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) throw new Error("Supabase server configuration is incomplete");
  return createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function cleanText(value: unknown, maximumLength: number): string {
  return typeof value === "string"
    ? value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, maximumLength)
    : "";
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}
