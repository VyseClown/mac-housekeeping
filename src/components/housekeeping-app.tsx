"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { FolderSearch, RefreshCw, Shield, Workflow } from "lucide-react";

import { CleanupView } from "@/components/cleanup-view";
import { ProcessView } from "@/components/process-view";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatBytes, formatRelativeTime } from "@/lib/format";
import type { ActionResult, Snapshot } from "@/lib/types";

type View = "cleanup" | "processes";
type Status = "loading" | "ready" | "error";

function hasProcessesPayload(snapshot: Snapshot | null): boolean {
  if (!snapshot) return false;
  if (snapshot.source === "mock") return true;
  return snapshot.included?.processes !== false;
}

export function HousekeepingApp({
  initialSnapshot,
  initialView = "cleanup",
}: {
  initialSnapshot?: Snapshot;
  initialView?: View;
}) {
  const [status, setStatus] = useState<Status>(initialSnapshot ? "ready" : "loading");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [snapshot, setSnapshot] = useState<Snapshot | null>(initialSnapshot ?? null);
  const [view, setView] = useState<View>(initialView);
  const [selectedId, setSelectedId] = useState<string | null>(
    initialSnapshot?.cleanupItems[0]?.id ?? null
  );
  const [selectedPid, setSelectedPid] = useState<number | null>(
    initialSnapshot?.processes[0]?.pid ?? null
  );
  const [pending, setPending] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingProcesses, setLoadingProcesses] = useState(false);
  const processesRequested = useRef(hasProcessesPayload(initialSnapshot ?? null));

  const applySnapshot = useCallback((data: Snapshot) => {
    setSnapshot(data);
    setSelectedId((current) =>
      current && data.cleanupItems.some((item) => item.id === current)
        ? current
        : (data.cleanupItems[0]?.id ?? null)
    );
    setSelectedPid((current) =>
      current && data.processes.some((process) => process.pid === current)
        ? current
        : (data.processes[0]?.pid ?? null)
    );
    setStatus("ready");
  }, []);

  const load = useCallback(async (tab: View | "all", signal?: AbortSignal) => {
    const query = tab === "all" ? "" : `?tab=${tab}`;
    const response = await fetch(`/api/snapshot${query}`, {
      cache: "no-store",
      signal,
    });
    if (!response.ok) {
      const body = (await response.json().catch(() => null)) as {
        error?: string;
      } | null;
      throw new Error(body?.error ?? `Snapshot failed (${response.status}).`);
    }
    return (await response.json()) as Snapshot;
  }, []);

  useEffect(() => {
    if (initialSnapshot) return;
    const controller = new AbortController();
    load("cleanup", controller.signal)
      .then((data) => {
        if (!controller.signal.aborted) applySnapshot(data);
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;
        setError(
          cause instanceof Error
            ? cause.message
            : "Could not collect a housekeeping snapshot."
        );
        setStatus("error");
      });
    return () => {
      controller.abort();
    };
  }, [applySnapshot, initialSnapshot, load]);

  useEffect(() => {
    if (view !== "processes" || hasProcessesPayload(snapshot) || processesRequested.current) {
      return;
    }
    processesRequested.current = true;
    const controller = new AbortController();
    setLoadingProcesses(true);
    load("processes", controller.signal)
      .then((data) => {
        if (!controller.signal.aborted) applySnapshot(data);
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) {
          processesRequested.current = false;
          return;
        }
        processesRequested.current = false;
        setError(
          cause instanceof Error
            ? cause.message
            : "Could not collect processes."
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoadingProcesses(false);
      });
    return () => {
      controller.abort();
    };
  }, [applySnapshot, load, snapshot, view]);

  function refresh() {
    setError(null);
    setRefreshing(true);
    if (!snapshot) setStatus("loading");
    void load("all")
      .then(applySnapshot)
      .catch((cause: unknown) => {
        setError(
          cause instanceof Error
            ? cause.message
            : "Could not collect a housekeeping snapshot."
        );
        if (!snapshot) setStatus("error");
      })
      .finally(() => setRefreshing(false));
  }

  async function runAction(body: Record<string, unknown>) {
    setPending(true);
    setNotice(null);
    setError(null);
    try {
      const response = await fetch("/api/actions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const result = (await response.json()) as ActionResult & { error?: string };
      if (!response.ok || !result.ok) {
        throw new Error(result.message ?? result.error ?? "Action blocked.");
      }
      setSnapshot(result.snapshot);
      setNotice(result.message);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Action failed.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8">
      <header className="space-y-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-1.5">
            <p className="text-xs font-medium tracking-[0.16em] text-muted-foreground uppercase">
              Alessandro Gentil
            </p>
            <h1 className="font-heading text-2xl font-medium tracking-tight sm:text-3xl">
              Mac Housekeeping
            </h1>
            <p className="max-w-2xl text-sm text-muted-foreground sm:text-[15px]">
              Investigation leftovers and already-used images or videos. Maps
              each path to the process holding it, then shows how to validate
              usage. nightshift and ai-memory stay.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {snapshot ? (
              <Badge variant="outline" className="rounded-md">
                {snapshot.source === "macos" ? "Live macOS" : "Mock Mac data"}
              </Badge>
            ) : null}
            <Button
              variant="outline"
              onClick={refresh}
              disabled={refreshing || status === "loading"}
              aria-busy={refreshing}
            >
              <RefreshCw
                data-icon="inline-start"
                className={refreshing ? "animate-spin" : undefined}
              />
              {refreshing ? "Refreshing…" : "Refresh"}
            </Button>
          </div>
        </div>

        {snapshot ? <StatRow snapshot={snapshot} /> : null}
        {snapshot ? <ProtectedNote snapshot={snapshot} /> : null}
        {snapshot?.warnings.map((warning) => (
          <p key={warning} className="text-xs text-muted-foreground">
            {warning}
          </p>
        ))}
      </header>

      {notice ? (
        <Alert>
          <AlertTitle>Action recorded</AlertTitle>
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      ) : null}

      {status === "error" && error && !snapshot ? (
        <Alert variant="destructive">
          <AlertTitle>Snapshot failed</AlertTitle>
          <AlertDescription>
            {error}{" "}
            <button type="button" className="underline" onClick={refresh}>
              Retry
            </button>
          </AlertDescription>
        </Alert>
      ) : null}

      {snapshot && error ? (
        <Alert variant="destructive">
          <AlertTitle>{status === "error" ? "Snapshot failed" : "Action blocked"}</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      ) : null}

      {status === "loading" && !snapshot ? <LoadingState /> : null}

      {snapshot ? (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <div className="inline-flex w-full sm:w-fit items-center gap-1 rounded-lg bg-muted p-1">
              <button
                id="tab-cleanup"
                type="button"
                aria-pressed={view === "cleanup"}
                className={cn(
                  "inline-flex min-h-10 flex-1 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium sm:flex-none",
                  view === "cleanup"
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground"
                )}
                onClick={() => setView("cleanup")}
              >
                <FolderSearch className="size-4" />
                Cleanup
              </button>
              <button
                id="tab-processes"
                type="button"
                aria-pressed={view === "processes"}
                className={cn(
                  "inline-flex min-h-10 flex-1 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium sm:flex-none",
                  view === "processes"
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground"
                )}
                onClick={() => setView("processes")}
              >
                <Workflow className="size-4" />
                Processes
              </button>
            </div>
            <p className="text-sm text-muted-foreground" data-current-view={view}>
              Now showing: {view === "cleanup" ? "Cleanup leftovers" : "Processes and simulators"}
            </p>
          </div>
          {view === "cleanup" ? (
            <CleanupView
              snapshot={snapshot}
              selectedId={selectedId}
              onSelect={setSelectedId}
              pending={pending}
              onDelete={(id) => runAction({ type: "delete-item", id })}
            />
          ) : loadingProcesses && !hasProcessesPayload(snapshot) ? (
            <p className="text-sm text-muted-foreground">Collecting processes…</p>
          ) : (
            <ProcessView
              snapshot={snapshot}
              selectedPid={selectedPid}
              onSelect={setSelectedPid}
              pending={pending}
              onKill={(pid) => runAction({ type: "kill-process", pid })}
              onCloseSimulator={(udid) =>
                runAction({ type: "close-simulator", udid })
              }
            />
          )}
        </div>
      ) : null}
    </div>
  );
}

function StatRow({ snapshot }: { snapshot: Snapshot }) {
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <Stat
        label="Reclaimable"
        value={formatBytes(snapshot.totals.reclaimableBytes)}
        hint="Idle leftovers only"
      />
      <Stat
        label="Held in use"
        value={formatBytes(snapshot.totals.inUseBytes)}
        hint="Open handles present"
      />
      <Stat
        label="Protected"
        value={`${snapshot.totals.protectedCount}`}
        hint="nightshift + ai-memory"
      />
      <Stat
        label="Collected"
        value={formatRelativeTime(snapshot.collectedAt)}
        hint={snapshot.host.hostname}
      />
    </div>
  );
}

function Stat({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint: string;
}) {
  return (
    <div className="rounded-xl bg-card px-3 py-3 ring-1 ring-foreground/10">
      <div className="text-[11px] tracking-wide text-muted-foreground uppercase">
        {label}
      </div>
      <div className="mt-1 font-heading text-lg font-medium">{value}</div>
      <div className="text-xs text-muted-foreground">{hint}</div>
    </div>
  );
}

function LoadingState() {
  return (
    <div className="space-y-3" aria-busy="true" aria-live="polite">
      <p className="text-sm text-muted-foreground">Collecting snapshot…</p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <Skeleton key={index} className="h-20 rounded-xl" />
        ))}
      </div>
      <Skeleton className="h-10 w-56 rounded-lg" />
      <Skeleton className="h-72 rounded-xl" />
    </div>
  );
}

function ProtectedNote({ snapshot }: { snapshot: Snapshot }) {
  return (
    <div className="flex items-start gap-3 rounded-xl bg-card px-3 py-3 text-sm ring-1 ring-foreground/10">
      <Shield className="mt-0.5 size-4 shrink-0" />
      <div className="min-w-0 space-y-1">
        <p>
          nightshift and ai-memory stay. They are never flagged or deleted.
        </p>
        <ul className="space-y-0.5 font-mono text-[11px] text-muted-foreground">
          {snapshot.protectedKeeps.map((keep) => (
            <li key={keep.path}>
              {keep.path}
              {keep.present ? "" : " · not on this host"}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
