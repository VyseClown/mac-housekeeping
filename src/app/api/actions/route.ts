import { performAction } from "@/lib/actions";
import type { HousekeepingAction } from "@/lib/types";

export const dynamic = "force-dynamic";

function parseAction(body: unknown): HousekeepingAction | null {
  if (!body || typeof body !== "object") return null;
  const record = body as Record<string, unknown>;
  if (record.type === "delete-item" && typeof record.id === "string") {
    return { type: "delete-item", id: record.id };
  }
  if (record.type === "kill-process" && typeof record.pid === "number") {
    return { type: "kill-process", pid: record.pid };
  }
  if (record.type === "close-simulator" && typeof record.udid === "string") {
    return { type: "close-simulator", udid: record.udid };
  }
  return null;
}

export async function POST(request: Request) {
  try {
    const action = parseAction(await request.json());
    if (!action) {
      return Response.json({ error: "Unrecognized action." }, { status: 400 });
    }
    const result = await performAction(action);
    return Response.json(result, { status: result.ok ? 200 : 409 });
  } catch (error) {
    return Response.json(
      {
        error:
          error instanceof Error ? error.message : "Action failed.",
      },
      { status: 500 }
    );
  }
}
