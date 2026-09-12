import { HousekeepingApp } from "@/components/housekeeping-app";
import { collectSnapshot } from "@/lib/collect";

export const dynamic = "force-dynamic";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ view?: string }>;
}) {
  const params = await searchParams;
  const initialSnapshot = await collectSnapshot({ tab: "cleanup" });
  return (
    <HousekeepingApp
      initialSnapshot={initialSnapshot}
      initialView={params.view === "processes" ? "processes" : "cleanup"}
    />
  );
}
