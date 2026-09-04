import { createClient } from "npm:@supabase/supabase-js@2";
import {
  PDFDocument,
  StandardFonts,
  rgb,
  type PDFPage,
  type PDFFont,
} from "npm:pdf-lib@1.17.1";

type ReportKind = "daily" | "weekly";
type Preference = {
  user_id: string;
  daily_enabled: boolean;
  daily_hour: number;
  daily_minute: number;
  weekly_enabled: boolean;
  weekly_weekday: number;
  weekly_hour: number;
  weekly_minute: number;
  time_zone: string;
  recipients: string[];
  cc: string[];
  report_detail: "detailed" | "compact";
  include_coordinates: boolean;
  include_technician: boolean;
  technician_name: string;
  company_name: string;
  reply_to: string | null;
};
type TripDay = {
  id: string;
  started_at: string;
  ended_at: string;
  payload: {
    id: string;
    startedAt: string;
    endedAt?: string;
    points?: Array<{ latitude: number; longitude: number; timestamp: string }>;
    stops?: Array<{
      id: string;
      arrival: string;
      departure?: string;
      latitude: number;
      longitude: number;
      accountName?: string;
      accountAddress?: string;
      technicianNote?: string;
      isPersonal?: boolean;
    }>;
  };
};

const supabaseURL = requireEnv("SUPABASE_URL");
const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const resendAPIKey = requireEnv("RESEND_API_KEY");
const cronSecret = requireEnv("TRIP_LOG_CRON_SECRET");
const sender = Deno.env.get("RESEND_FROM") ?? "FireVault Reports <reports@mail.bannerman.us>";
const fallbackReplyTo = Deno.env.get("REPORT_REPLY_TO") ?? undefined;
const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (request) => {
  try {
    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
    const isCron = request.headers.get("x-trip-log-cron-secret") === cronSecret;
    const userID = isCron ? undefined : await authenticatedUserID(request);
    if (!isCron && !userID) return json({ error: "Unauthorized" }, 401);

    const now = new Date();
    let preferenceQuery = admin.from("trip_log_report_preferences").select("*");
    const requestedUserID = userID ?? (typeof body.user_id === "string" ? body.user_id : undefined);
    if (requestedUserID) preferenceQuery = preferenceQuery.eq("user_id", requestedUserID);
    const { data: preferences, error } = await preferenceQuery;
    if (error) throw error;

    let sent = 0;
    let skipped = 0;
    for (const preference of (preferences ?? []) as Preference[]) {
      const requestedKind = body.kind as ReportKind | undefined;
      const kinds: ReportKind[] = requestedKind ? [requestedKind] : ["daily", "weekly"];
      for (const kind of kinds) {
        const force = Boolean(body.force) && Boolean(userID);
        if (!force && !isDue(preference, kind, now)) continue;
        try {
          const result = await deliver(preference, kind, now, force);
          result === "sent" ? sent++ : skipped++;
        } catch (error) {
          console.error(`Trip Log ${kind} delivery failed for ${preference.user_id}`, error);
          skipped++;
        }
      }
    }
    return json({ ok: true, sent, skipped });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Report dispatch failed" }, 500);
  }
});

async function authenticatedUserID(request: Request): Promise<string | undefined> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.toLowerCase().startsWith("bearer ")) return undefined;
  const token = authorization.slice(7);
  const { data, error } = await admin.auth.getUser(token);
  return error ? undefined : data.user?.id;
}

async function deliver(
  preference: Preference,
  kind: ReportKind,
  now: Date,
  force: boolean,
): Promise<"sent" | "skipped"> {
  const periodStart = periodStartFor(preference.time_zone, kind, now);
  if (!force) {
    const { data: existing } = await admin
      .from("trip_log_report_deliveries")
      .select("status,attempts")
      .eq("user_id", preference.user_id)
      .eq("report_type", kind)
      .eq("period_start", periodStart)
      .maybeSingle();
    if (existing?.status === "sent" || (existing?.attempts ?? 0) >= 3) return "skipped";
  }
  if (!preference.recipients?.length) return "skipped";

  const range = reportRange(preference.time_zone, kind, now);
  const { data: days, error } = await admin
    .from("trip_log_days")
    .select("id,started_at,ended_at,payload")
    .eq("user_id", preference.user_id)
    .gte("started_at", range.start.toISOString())
    .lt("started_at", range.end.toISOString())
    .order("started_at");
  if (error) throw error;
  if (!days?.length) return "skipped";

  const scheduledFor = now.toISOString();
  const { data: delivery, error: deliveryError } = await admin
    .from("trip_log_report_deliveries")
    .upsert({
      user_id: preference.user_id,
      report_type: kind,
      period_start: periodStart,
      status: "processing",
      scheduled_for: scheduledFor,
      updated_at: scheduledFor,
    }, { onConflict: "user_id,report_type,period_start" })
    .select("id,attempts")
    .single();
  if (deliveryError) throw deliveryError;

  await admin.from("trip_log_report_deliveries").update({
    attempts: (delivery.attempts ?? 0) + 1,
    updated_at: scheduledFor,
  }).eq("id", delivery.id);

  try {
    const pdf = await buildPDF(kind, preference, days as TripDay[], periodStart);
    const filename = `FireVault-Trip-Log-${kind === "daily" ? "Daily" : "Weekly"}-${periodStart}.pdf`;
    const subject = kind === "daily"
      ? `FireVault Trip Log Daily Report — ${periodStart}`
      : `FireVault Trip Log Weekly Report — ${periodStart}`;
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendAPIKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `trip-log/${preference.user_id}/${kind}/${periodStart}`,
      },
      body: JSON.stringify({
        from: sender,
        to: preference.recipients,
        cc: preference.cc ?? [],
        reply_to: preference.reply_to ?? fallbackReplyTo,
        subject,
        html: emailHTML(kind, preference, days as TripDay[], periodStart),
        attachments: [{ filename, content: toBase64(pdf) }],
      }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result?.message ?? `Resend returned ${response.status}`);

    await admin.from("trip_log_report_deliveries").update({
      status: "sent",
      sent_at: new Date().toISOString(),
      resend_email_id: result.id,
      last_error: null,
      updated_at: new Date().toISOString(),
    }).eq("id", delivery.id);
    return "sent";
  } catch (error) {
    await admin.from("trip_log_report_deliveries").update({
      status: "failed",
      last_error: String(error).slice(0, 1000),
      updated_at: new Date().toISOString(),
    }).eq("id", delivery.id);
    throw error;
  }
}

function isDue(preference: Preference, kind: ReportKind, now: Date): boolean {
  const parts = localParts(now, preference.time_zone);
  if (kind === "daily") {
    return preference.daily_enabled &&
      parts.hour === preference.daily_hour &&
      Math.abs(parts.minute - preference.daily_minute) < 5;
  }
  return preference.weekly_enabled &&
    parts.weekday === preference.weekly_weekday &&
    parts.hour === preference.weekly_hour &&
    Math.abs(parts.minute - preference.weekly_minute) < 5;
}

function localParts(date: Date, timeZone: string) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const values = Object.fromEntries(
    formatter.formatToParts(date).filter((p) => p.type !== "literal").map((p) => [p.type, p.value]),
  );
  const weekdays: Record<string, number> = {
    Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7,
  };
  return {
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hour: Number(values.hour),
    minute: Number(values.minute),
    weekday: weekdays[values.weekday],
  };
}

function periodStartFor(timeZone: string, kind: ReportKind, now: Date): string {
  const parts = localParts(now, timeZone);
  const local = new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
  if (kind === "daily") return local.toISOString().slice(0, 10);
  const mondayOffset = (parts.weekday + 5) % 7;
  local.setUTCDate(local.getUTCDate() - mondayOffset);
  return local.toISOString().slice(0, 10);
}

function reportRange(timeZone: string, kind: ReportKind, now: Date) {
  const periodStart = periodStartFor(timeZone, kind, now);
  const start = zonedMidnight(periodStart, timeZone);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + (kind === "daily" ? 1 : 7));
  return { start, end };
}

function zonedMidnight(isoDate: string, timeZone: string): Date {
  const [year, month, day] = isoDate.split("-").map(Number);
  let guess = new Date(Date.UTC(year, month - 1, day));
  const parts = localParts(guess, timeZone);
  const desired = Date.UTC(year, month - 1, day);
  const actual = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute);
  guess = new Date(guess.getTime() + desired - actual);
  return guess;
}

async function buildPDF(
  kind: ReportKind,
  preference: Preference,
  days: TripDay[],
  periodStart: string,
): Promise<Uint8Array> {
  const document = await PDFDocument.create();
  const regular = await document.embedFont(StandardFonts.Helvetica);
  const bold = await document.embedFont(StandardFonts.HelveticaBold);
  let page = document.addPage([612, 792]);
  let y = drawHeader(page, bold, regular, kind, preference, periodStart);
  y = drawSummary(page, bold, regular, days, y);
  y = drawRoute(page, days, y);

  for (const day of days) {
    const stops = day.payload.stops ?? [];
    if (y < 145) {
      page = document.addPage([612, 792]);
      y = drawContinuationHeader(page, bold, regular, kind, periodStart);
    }
    page.drawText(formatDate(day.started_at, preference.time_zone), {
      x: 42, y, size: 12, font: bold, color: navy,
    });
    y -= 20;
    for (const [index, stop] of stops.entries()) {
      if (y < 72) {
        page = document.addPage([612, 792]);
        y = drawContinuationHeader(page, bold, regular, kind, periodStart);
      }
      const title = stop.isPersonal ? "Personal Stop" : stop.accountName ?? "Unrecognized Stop";
      const detail = stop.isPersonal ? "Private details redacted" : stop.accountAddress ?? "";
      const duration = durationText(stop.arrival, stop.departure);
      page.drawText(`${index + 1}`, { x: 42, y, size: 9, font: bold, color: blue });
      page.drawText(formatTime(stop.arrival, preference.time_zone), { x: 64, y, size: 9, font: regular, color: navy });
      page.drawText(fit(title, 52), { x: 124, y, size: 9, font: bold, color: navy });
      page.drawText(duration, { x: 515, y, size: 9, font: regular, color: navy });
      y -= 13;
      if (detail) {
        page.drawText(fit(detail, 70), { x: 124, y, size: 8, font: regular, color: gray });
        y -= 12;
      }
      if (preference.report_detail === "detailed" && !stop.isPersonal && stop.technicianNote) {
        page.drawText(`Note: ${fit(stop.technicianNote, 68)}`, { x: 124, y, size: 8, font: regular, color: gray });
        y -= 12;
      }
      y -= 7;
      page.drawLine({ start: { x: 42, y }, end: { x: 570, y }, thickness: 0.5, color: line });
      y -= 12;
    }
    if (!stops.length) {
      page.drawText("No logged stops for this workday.", { x: 64, y, size: 9, font: regular, color: gray });
      y -= 24;
    }
  }
  return document.save();
}

function drawHeader(
  page: PDFPage,
  bold: PDFFont,
  regular: PDFFont,
  kind: ReportKind,
  preference: Preference,
  periodStart: string,
): number {
  page.drawRectangle({ x: 0, y: 706, width: 612, height: 86, color: navy });
  page.drawText("FIRE", { x: 42, y: 754, size: 24, font: bold, color: red });
  page.drawText("VAULT", { x: 94, y: 754, size: 24, font: bold, color: rgb(1, 1, 1) });
  page.drawText(`${kind === "daily" ? "DAILY" : "WEEKLY"} TRIP LOG REPORT`, {
    x: 42, y: 730, size: 11, font: bold, color: rgb(0.72, 0.84, 1),
  });
  const tech = preference.include_technician
    ? [preference.technician_name, preference.company_name].filter(Boolean).join(" • ")
    : "";
  if (tech) page.drawText(fit(tech, 65), { x: 300, y: 756, size: 9, font: regular, color: rgb(1, 1, 1) });
  page.drawText(periodStart, { x: 480, y: 730, size: 10, font: bold, color: rgb(1, 1, 1) });
  return 680;
}

function drawContinuationHeader(
  page: PDFPage,
  bold: PDFFont,
  regular: PDFFont,
  kind: ReportKind,
  periodStart: string,
): number {
  page.drawText("FIREVAULT", { x: 42, y: 755, size: 13, font: bold, color: navy });
  page.drawText(`${kind.toUpperCase()} TRIP LOG - ${periodStart}`, {
    x: 410, y: 755, size: 8, font: regular, color: gray,
  });
  page.drawLine({ start: { x: 42, y: 743 }, end: { x: 570, y: 743 }, thickness: 1, color: line });
  return 720;
}

function drawSummary(page: PDFPage, bold: PDFFont, regular: PDFFont, days: TripDay[], y: number): number {
  const stops = days.flatMap((day) => day.payload.stops ?? []);
  const points = days.flatMap((day) => day.payload.points ?? []);
  const distance = routeDistance(points);
  const elapsed = days.reduce((sum, day) => sum + Math.max(0, Date.parse(day.ended_at) - Date.parse(day.started_at)), 0);
  const values = [
    ["DISTANCE", `${distance.toFixed(1)} mi`],
    ["TIME", compactDuration(elapsed)],
    ["STOPS", String(stops.length)],
    ["WORKDAYS", String(days.length)],
  ];
  page.drawRectangle({ x: 42, y: y - 56, width: 528, height: 56, color: paleBlue });
  values.forEach(([label, value], index) => {
    const x = 62 + index * 132;
    page.drawText(value, { x, y: y - 25, size: 14, font: bold, color: navy });
    page.drawText(label, { x, y: y - 42, size: 7, font: bold, color: gray });
  });
  return y - 76;
}

function drawRoute(page: PDFPage, days: TripDay[], y: number): number {
  const points = days.flatMap((day) => day.payload.points ?? []);
  page.drawText("ROUTE OVERVIEW", { x: 42, y, size: 9, color: navy });
  const box = { x: 42, y: y - 150, width: 528, height: 136 };
  page.drawRectangle({ ...box, color: rgb(0.96, 0.97, 0.98), borderColor: line, borderWidth: 1 });
  if (points.length > 1) {
    const latitudes = points.map((p) => p.latitude);
    const longitudes = points.map((p) => p.longitude);
    const minLat = Math.min(...latitudes), maxLat = Math.max(...latitudes);
    const minLon = Math.min(...longitudes), maxLon = Math.max(...longitudes);
    const latSpan = Math.max(0.0001, maxLat - minLat);
    const lonSpan = Math.max(0.0001, maxLon - minLon);
    const xy = (point: { latitude: number; longitude: number }) => ({
      x: box.x + 12 + ((point.longitude - minLon) / lonSpan) * (box.width - 24),
      y: box.y + 12 + ((point.latitude - minLat) / latSpan) * (box.height - 24),
    });
    for (let index = 1; index < points.length; index++) {
      page.drawLine({ start: xy(points[index - 1]), end: xy(points[index]), thickness: 2.5, color: blue });
    }
  } else {
    page.drawText("No route geometry recorded.", { x: 210, y: box.y + 62, size: 10, color: gray });
  }
  return y - 170;
}

function emailHTML(kind: ReportKind, preference: Preference, days: TripDay[], periodStart: string): string {
  const stops = days.reduce((sum, day) => sum + (day.payload.stops?.length ?? 0), 0);
  const title = kind === "daily" ? "Daily Trip Log" : "Weekly Trip Log";
  return `<!doctype html><html><body style="margin:0;background:#f3f6fa;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#13233f">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:30px">
  <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:white;border-radius:16px;overflow:hidden">
  <tr><td style="background:#13233f;padding:26px 32px"><span style="font-size:24px;font-weight:800;color:#e63b38">FIRE</span><span style="font-size:24px;font-weight:800;color:white">VAULT</span></td></tr>
  <tr><td style="padding:32px"><h1 style="margin:0 0 8px;font-size:24px">${title}</h1>
  <p style="margin:0 0 24px;color:#5d6879">${periodStart} • ${days.length} workday${days.length === 1 ? "" : "s"} • ${stops} logged stop${stops === 1 ? "" : "s"}</p>
  <p>Your FireVault Trip Log PDF is attached.</p>
  ${preference.technician_name ? `<p style="color:#5d6879">Prepared for ${escapeHTML(preference.technician_name)}</p>` : ""}
  </td></tr></table></td></tr></table></body></html>`;
}

function routeDistance(points: Array<{ latitude: number; longitude: number }>): number {
  let meters = 0;
  for (let index = 1; index < points.length; index++) {
    const a = points[index - 1], b = points[index];
    const p1 = a.latitude * Math.PI / 180, p2 = b.latitude * Math.PI / 180;
    const dp = (b.latitude - a.latitude) * Math.PI / 180;
    const dl = (b.longitude - a.longitude) * Math.PI / 180;
    const h = Math.sin(dp / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
    meters += 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
  }
  return meters / 1609.344;
}

function durationText(start: string, end?: string): string {
  if (!end) return "Open";
  return compactDuration(Math.max(0, Date.parse(end) - Date.parse(start)));
}
function compactDuration(milliseconds: number): string {
  const minutes = Math.round(milliseconds / 60000);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes}m`;
}
function formatDate(value: string, timeZone: string): string {
  return pdfText(new Intl.DateTimeFormat("en-US", { timeZone, weekday: "long", month: "long", day: "numeric", year: "numeric" }).format(new Date(value)));
}
function formatTime(value: string, timeZone: string): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone,
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).formatToParts(new Date(value)).filter(part => part.type !== "literal").map(part => [part.type, part.value]));
  return `${parts.hour}:${parts.minute} ${parts.dayPeriod}`;
}
function fit(value: string, length: number): string {
  const safe = pdfText(value);
  return safe.length <= length ? safe : `${safe.slice(0, Math.max(0, length - 3))}...`;
}
function pdfText(value: string): string {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[\u00a0\u202f]/g, " ")
    .replace(/[\u2013\u2014]/g, "-")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201c\u201d]/g, '"')
    .replace(/\u2026/g, "...")
    .replace(/[^\x20-\x7e]/g, "?");
}
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  }
  return btoa(binary);
}
function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  }[character] ?? character));
}
function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}
function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const navy = rgb(0.075, 0.137, 0.247);
const blue = rgb(0.10, 0.42, 0.86);
const red = rgb(0.90, 0.18, 0.17);
const gray = rgb(0.37, 0.41, 0.48);
const line = rgb(0.82, 0.85, 0.89);
const paleBlue = rgb(0.92, 0.96, 1);
