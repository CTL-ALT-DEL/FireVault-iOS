type LookupRequest = {
  latitude?: unknown;
  longitude?: unknown;
  radiusMeters?: unknown;
};

type GooglePlace = {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  primaryType?: string;
  businessStatus?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("authorization");
    if (!authorization?.toLowerCase().startsWith("bearer ")) {
      return json({ error: "Unauthorized" }, 401);
    }

    const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY") ?? Deno.env.get("GOOGLE_MAPS_API_KEY");
    if (!apiKey) {
      console.error("Google Places lookup is missing its API key secret");
      return json({ error: "Google Places is not configured" }, 503);
    }

    const body = await request.json().catch(() => ({})) as LookupRequest;
    const latitude = finiteNumber(body.latitude);
    const longitude = finiteNumber(body.longitude);
    if (
      latitude === undefined || longitude === undefined ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180
    ) {
      return json({ error: "Valid stop coordinates are required" }, 400);
    }

    const requestedRadius = finiteNumber(body.radiusMeters) ?? 125;
    const radius = Math.min(250, Math.max(25, requestedRadius));
    const googleResponse = await fetch("https://places.googleapis.com/v1/places:searchNearby", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": [
          "places.id",
          "places.displayName",
          "places.formattedAddress",
          "places.location",
          "places.primaryType",
          "places.businessStatus",
        ].join(","),
      },
      body: JSON.stringify({
        maxResultCount: 8,
        rankPreference: "DISTANCE",
        languageCode: "en",
        locationRestriction: {
          circle: {
            center: { latitude, longitude },
            radius,
          },
        },
      }),
    });

    if (!googleResponse.ok) {
      const requestID = googleResponse.headers.get("x-request-id") ?? "unavailable";
      console.error(`Google Places request failed (${googleResponse.status}, request ${requestID})`);
      return json({ error: "Google Places lookup failed" }, 502);
    }

    const payload = await googleResponse.json() as { places?: GooglePlace[] };
    const matches = (payload.places ?? [])
      .filter((place) => place.businessStatus !== "CLOSED_PERMANENTLY")
      .flatMap((place) => {
        const name = place.displayName?.text?.trim();
        const address = place.formattedAddress?.trim();
        const placeLatitude = place.location?.latitude;
        const placeLongitude = place.location?.longitude;
        if (!place.id || !name || !address || placeLatitude === undefined || placeLongitude === undefined) {
          return [];
        }
        return [{
          placeID: place.id,
          name,
          address,
          distanceMeters: distanceMeters(latitude, longitude, placeLatitude, placeLongitude),
          primaryType: place.primaryType ?? null,
        }];
      })
      .sort((left, right) => left.distanceMeters - right.distanceMeters)
      .slice(0, 5);

    return json({ matches });
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Unexpected Google Places lookup error");
    return json({ error: "Google Places lookup failed" }, 500);
  }
});

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const earthRadius = 6_371_000;
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const deltaLatitude = radians(lat2 - lat1);
  const deltaLongitude = radians(lon2 - lon1);
  const a = Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(deltaLongitude / 2) ** 2;
  return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
