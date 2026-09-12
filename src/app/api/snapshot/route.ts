import { collectSnapshot } from "@/lib/collect";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const snapshot = await collectSnapshot();
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
