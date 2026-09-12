import { HousekeepingApp } from "@/components/housekeeping-app";
import { collectSnapshot } from "@/lib/collect";

export const dynamic = "force-dynamic";

export default async function Home() {
  const initialSnapshot = await collectSnapshot({ tab: "cleanup" });
  return <HousekeepingApp initialSnapshot={initialSnapshot} />;
}
