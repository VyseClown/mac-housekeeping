import { collectSnapshot, type SnapshotTab } from "@/lib/collect";

export const dynamic = "force-dynamic";

function parseTab(value: string | null): SnapshotTab {
  if (value === "cleanup" || value === "processes" || value === "all") {
    return value;
  }
  return "all";
}

export async function GET(request: Request) {
  try {
    const tab = parseTab(new URL(request.url).searchParams.get("tab"));
    const snapshot = await collectSnapshot({ tab });
    return Response.json(snapshot);
  } catch (error) {
    return Response.json(
      {
        error:
          error instanceof Error
            ? error.message
            : "Could not collect a housekeeping snapshot.",
      },
      { status: 500 }
    );
  }
}
