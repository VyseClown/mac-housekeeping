"use client";

import { useEffect, useState } from "react";
import { Crosshair } from "lucide-react";

import { ConfirmAction } from "@/components/confirm-action";
import { SimulatorList } from "@/components/simulator-list";
import { UsageBadge } from "@/components/usage-badge";
import { ProcessValidation } from "@/components/validation-panel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatBytes } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { ProcessInfo, Snapshot } from "@/lib/types";

export function ProcessView({
  snapshot,
  selectedPid,
  onSelect,
  onKill,
  onCloseSimulator,
  pending,
}: {
  snapshot: Snapshot;
  selectedPid: number | null;
  onSelect: (pid: number) => void;
  onKill: (pid: number) => Promise<void>;
  onCloseSimulator: (udid: string) => Promise<void>;
  pending: boolean;
}) {
  const [confirmPid, setConfirmPid] = useState<number | null>(null);
  const wide = useWideLayout();
  const selected =
    snapshot.processes.find((process) => process.pid === selectedPid) ?? null;
  const confirmProcess =
    snapshot.processes.find((process) => process.pid === confirmPid) ?? null;

  return (
    <div className="space-y-4">
      <h2 className="font-heading text-lg font-medium">Process map</h2>
      <SimulatorList
        simulators={snapshot.simulators}
        pending={pending}
        onClose={onCloseSimulator}
      />

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <div className="space-y-3">
          {snapshot.processes.length === 0 ? (
            <div className="rounded-xl border border-dashed bg-card/40 px-4 py-10 text-center">
              <p className="text-sm font-medium">No mapped developer processes</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Simulator, Xcode, leftover captures, and holders of cleanup
                paths would show here.
              </p>
            </div>
          ) : (
            <>
              {wide ? (
              <div className="overflow-hidden rounded-xl bg-card ring-1 ring-foreground/10">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Process</TableHead>
                      <TableHead className="w-20">PID</TableHead>
                      <TableHead className="w-32">Parent</TableHead>
                      <TableHead className="w-16">CPU</TableHead>
                      <TableHead>Holds</TableHead>
                      <TableHead className="w-24">Usage</TableHead>
                      <TableHead className="w-24" />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {snapshot.processes.map((process) => (
                      <TableRow
                        key={process.pid}
                        className={cn(
                          "cursor-pointer",
                          process.pid === selectedPid && "bg-accent/70"
                        )}
                        onClick={() => onSelect(process.pid)}
                      >
                        <TableCell>
                          <div className="font-medium">{process.name}</div>
                          <div className="text-[11px] text-muted-foreground">
                            {labelCategory(process)}
                          </div>
                        </TableCell>
                        <TableCell className="font-mono tabular-nums">
                          {process.pid}
                        </TableCell>
                        <TableCell className="text-muted-foreground">
                          {process.parentName}
                          <span className="block font-mono text-[11px]">
                            {process.ppid}
                          </span>
                        </TableCell>
                        <TableCell className="font-mono tabular-nums">
                          {process.cpu.toFixed(1)}
                        </TableCell>
                        <TableCell className="max-w-[16rem] whitespace-normal">
                          <HeldSummary process={process} />
                        </TableCell>
                        <TableCell>
                          <UsageBadge usage={process.usage} />
                        </TableCell>
                        <TableCell>
                          <KillButton
                            process={process}
                            onAsk={() => setConfirmPid(process.pid)}
                          />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
              ) : (
              <div className="grid gap-2">
                {snapshot.processes.map((process) => (
                  <Card
                    key={process.pid}
                    size="sm"
                    className={cn(
                      "cursor-pointer",
                      process.pid === selectedPid && "ring-foreground/20"
                    )}
                    onClick={() => onSelect(process.pid)}
                  >
                    <CardContent className="space-y-2">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <div className="font-medium">{process.name}</div>
                          <div className="font-mono text-[11px] text-muted-foreground">
                            pid {process.pid} · parent {process.parentName} (
                            {process.ppid})
                          </div>
                        </div>
                        <UsageBadge usage={process.usage} />
                      </div>
                      <HeldSummary process={process} />
                      <KillButton
                        process={process}
                        onAsk={() => setConfirmPid(process.pid)}
                      />
                    </CardContent>
                  </Card>
                ))}
              </div>
              )}
            </>
          )}
        </div>

        <aside className="rounded-xl bg-card p-4 ring-1 ring-foreground/10 lg:sticky lg:top-4 lg:self-start">
          {selected ? (
            <SelectedProcess
              process={selected}
              onAskKill={() => setConfirmPid(selected.pid)}
            />
          ) : (
            <p className="text-sm text-muted-foreground">
              Select a process to see the files it holds and how to localize it
              in Activity Monitor before any kill.
            </p>
          )}
        </aside>
      </div>

      <ConfirmAction
        open={confirmPid !== null}
        title="Send SIGTERM?"
        description={
          confirmProcess
            ? `${confirmProcess.name} (${confirmProcess.pid}), parent ${confirmProcess.parentName}. Not auto-killed. Confirm only after you localized it.`
            : "Nothing selected."
        }
        confirmLabel="Kill process"
        pending={pending}
        onOpenChange={(open) => {
          if (!open) setConfirmPid(null);
        }}
        onConfirm={async () => {
          if (confirmPid === null) return;
          await onKill(confirmPid);
          setConfirmPid(null);
        }}
      />
    </div>
  );
}

function useWideLayout() {
  const [wide, setWide] = useState(true);
  useEffect(() => {
    const media = window.matchMedia("(min-width: 768px)");
    const sync = () => setWide(media.matches);
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, []);
  return wide;
}

function SelectedProcess({
  process,
  onAskKill,
}: {
  process: ProcessInfo;
  onAskKill: () => void;
}) {
  const canKill =
    process.usage === "idle" &&
    !process.inUseByModels &&
    process.category !== "protected";

  return (
    <div className="space-y-4">
      <ProcessValidation process={process} />
      <Separator />
      <div className="space-y-2">
        <h3 className="text-sm font-medium">Files held</h3>
        {process.heldFiles.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No leftover, protected, or simulator files mapped.
          </p>
        ) : (
          <ul className="space-y-2">
            {process.heldFiles.map((file) => (
              <li key={file.path} className="space-y-0.5">
                <Badge variant="outline" className="rounded-md">
                  {file.role}
                </Badge>
                <div className="break-all font-mono text-[11px] text-muted-foreground">
                  {file.path}
                  {file.bytes ? ` · ${formatBytes(file.bytes)}` : ""}
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
      {canKill ? (
        <Button variant="destructive" className="w-full" onClick={onAskKill}>
          <Crosshair data-icon="inline-start" />
          Localize, then kill
        </Button>
      ) : (
        <p className="text-xs text-muted-foreground">
          {process.inUseByModels
            ? "Models are using this process. Kill stays off."
            : "Not classified as an idle leftover. Inspect parent and files first."}
        </p>
      )}
    </div>
  );
}

function KillButton({
  process,
  onAsk,
}: {
  process: ProcessInfo;
  onAsk: () => void;
}) {
  const locked =
    process.inUseByModels ||
    process.usage === "protected" ||
    process.usage !== "idle";
  return (
    <Button
      size="sm"
      variant={locked ? "outline" : "destructive"}
      disabled={locked}
      onClick={(event) => {
        event.stopPropagation();
        onAsk();
      }}
    >
      {process.inUseByModels ? "In use" : locked ? "Active" : "Kill"}
    </Button>
  );
}

function HeldSummary({ process }: { process: ProcessInfo }) {
  if (process.heldFiles.length === 0) {
    return <span className="text-muted-foreground">—</span>;
  }
  const leaf = process.heldFiles[0].path.split("/").filter(Boolean).at(-1);
  const extra = process.heldFiles.length - 1;
  return (
    <span className="text-xs">
      {leaf}
      {extra > 0 ? ` +${extra}` : ""}
    </span>
  );
}

function labelCategory(process: ProcessInfo): string {
  if (process.category === "simulator") return "Xcode Simulator";
  if (process.category === "xcode") return "Xcode";
  if (process.category === "idle-leftover") return "Idle leftover";
  if (process.category === "protected") return "Kept install";
  return "Developer";
}
