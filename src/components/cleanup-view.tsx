"use client";

import { useEffect, useMemo, useState } from "react";
import { Film, FolderSearch, Trash2 } from "lucide-react";

import { ConfirmAction } from "@/components/confirm-action";
import { SizeBar } from "@/components/size-bar";
import { UsageBadge } from "@/components/usage-badge";
import { PathValidation } from "@/components/validation-panel";
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
import { formatRelativeTime } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { CleanupItem, CleanupKind, Snapshot } from "@/lib/types";

type KindFilter = "all" | CleanupKind | "idle";

export function CleanupView({
  snapshot,
  selectedId,
  onSelect,
  onDelete,
  pending,
}: {
  snapshot: Snapshot;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onDelete: (id: string) => Promise<void>;
  pending: boolean;
}) {
  const [filter, setFilter] = useState<KindFilter>("all");
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const wide = useWideLayout();

  const items = useMemo(() => {
    return snapshot.cleanupItems.filter((item) => {
      if (filter === "idle") return item.usage === "idle";
      if (filter === "all") return true;
      return item.kind === filter;
    });
  }, [filter, snapshot.cleanupItems]);

  const maxBytes = Math.max(...snapshot.cleanupItems.map((item) => item.bytes), 1);
  const selected = snapshot.cleanupItems.find((item) => item.id === selectedId) ?? null;
  const confirmItem = snapshot.cleanupItems.find((item) => item.id === confirmId) ?? null;

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
      <div className="space-y-3">
        <div className="flex flex-wrap gap-1.5">
          <FilterChip
            active={filter === "all"}
            onClick={() => setFilter("all")}
            label="All leftovers"
          />
          <FilterChip
            active={filter === "investigation-leftover"}
            onClick={() => setFilter("investigation-leftover")}
            label="Investigation"
          />
          <FilterChip
            active={filter === "used-media"}
            onClick={() => setFilter("used-media")}
            label="Used media"
          />
          <FilterChip
            active={filter === "idle"}
            onClick={() => setFilter("idle")}
            label="Idle only"
          />
        </div>

        {items.length === 0 ? (
          <EmptyCleanup filter={filter} />
        ) : (
          <>
            {wide ? (
            <div className="overflow-hidden rounded-xl bg-card ring-1 ring-foreground/10">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[7.5rem]">Kind</TableHead>
                    <TableHead>Path</TableHead>
                    <TableHead className="w-32">Size</TableHead>
                    <TableHead className="w-28">Accessed</TableHead>
                    <TableHead className="w-24">Handles</TableHead>
                    <TableHead className="w-24">Usage</TableHead>
                    <TableHead className="w-20" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {items.map((item) => (
                    <TableRow
                      key={item.id}
                      data-state={item.id === selectedId ? "selected" : undefined}
                      className={cn(
                        "cursor-pointer",
                        item.id === selectedId && "bg-accent/70"
                      )}
                      onClick={() => onSelect(item.id)}
                    >
                      <TableCell>
                        <KindBadge kind={item.kind} />
                      </TableCell>
                      <TableCell className="max-w-[22rem] whitespace-normal">
                        <PathLabel path={item.path} />
                      </TableCell>
                      <TableCell>
                        <SizeBar bytes={item.bytes} maxBytes={maxBytes} />
                      </TableCell>
                      <TableCell className="text-muted-foreground">
                        {formatRelativeTime(item.lastAccessAt)}
                      </TableCell>
                      <TableCell className="font-mono tabular-nums">
                        {item.openHandles.length}
                      </TableCell>
                      <TableCell>
                        <UsageBadge usage={item.usage} />
                      </TableCell>
                      <TableCell>
                        <DeleteButton
                          item={item}
                          onAsk={() => setConfirmId(item.id)}
                        />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            ) : (
            <div className="grid gap-2">
              {items.map((item) => (
                <Card
                  key={item.id}
                  size="sm"
                  className={cn(
                    "cursor-pointer",
                    item.id === selectedId && "ring-foreground/20"
                  )}
                  onClick={() => onSelect(item.id)}
                >
                  <CardContent className="space-y-3">
                    <div className="flex items-start justify-between gap-2">
                      <KindBadge kind={item.kind} />
                      <UsageBadge usage={item.usage} />
                    </div>
                    <PathLabel path={item.path} />
                    <SizeBar bytes={item.bytes} maxBytes={maxBytes} />
                    <div className="flex items-center justify-between text-xs text-muted-foreground">
                      <span>{formatRelativeTime(item.lastAccessAt)}</span>
                      <span>{item.openHandles.length} open handles</span>
                    </div>
                    <DeleteButton
                      item={item}
                      onAsk={() => setConfirmId(item.id)}
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
          <SelectedCleanup
            item={selected}
            snapshot={snapshot}
            onAskDelete={() => setConfirmId(selected.id)}
          />
        ) : (
          <p className="text-sm text-muted-foreground">
            Select a leftover to see size, holders, and the four usage checks:
            open handles, last access, parent process, idle vs in use.
          </p>
        )}
      </aside>

      <ConfirmAction
        open={confirmId !== null}
        title="Delete this leftover?"
        description={
          confirmItem
            ? `${confirmItem.path} is idle and not nightshift or ai-memory. Nothing deletes until you confirm.`
            : "Nothing selected."
        }
        confirmLabel="Delete leftover"
        pending={pending}
        onOpenChange={(open) => {
          if (!open) setConfirmId(null);
        }}
        onConfirm={async () => {
          if (!confirmId) return;
          await onDelete(confirmId);
          setConfirmId(null);
        }}
      />
    </div>
  );
}

function SelectedCleanup({
  item,
  snapshot,
  onAskDelete,
}: {
  item: CleanupItem;
  snapshot: Snapshot;
  onAskDelete: () => void;
}) {
  const holders = snapshot.processes.filter((process) =>
    process.heldFiles.some(
      (file) =>
        file.path === item.path ||
        file.path.startsWith(item.path) ||
        item.path.startsWith(file.path)
    ) || item.openHandles.some((handle) => handle.pid === process.pid)
  );

  return (
    <div className="space-y-4">
      <PathValidation item={item} />
      <Separator />
      <div className="space-y-2">
        <h3 className="text-sm font-medium">Processes using it</h3>
        {holders.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No mapped process holds this path.
          </p>
        ) : (
          <ul className="space-y-1.5 text-sm">
            {holders.map((process) => (
              <li key={process.pid} className="font-mono text-xs">
                {process.name} · {process.pid} · parent {process.parentName}
              </li>
            ))}
          </ul>
        )}
      </div>
      {item.usage === "idle" ? (
        <Button variant="destructive" className="w-full" onClick={onAskDelete}>
          <Trash2 data-icon="inline-start" />
          Review delete
        </Button>
      ) : (
        <p className="text-xs text-muted-foreground">
          Delete stays locked until handles are gone and usage reads idle.
        </p>
      )}
    </div>
  );
}

function DeleteButton({
  item,
  onAsk,
}: {
  item: CleanupItem;
  onAsk: () => void;
}) {
  const locked = item.usage !== "idle";
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
      {locked ? "Held" : "Delete"}
    </Button>
  );
}

function KindBadge({ kind }: { kind: CleanupKind }) {
  const investigation = kind === "investigation-leftover";
  return (
    <Badge variant="secondary" className="rounded-md">
      {investigation ? (
        <FolderSearch data-icon="inline-start" />
      ) : (
        <Film data-icon="inline-start" />
      )}
      {investigation ? "Investigation" : "Used media"}
    </Badge>
  );
}

function PathLabel({ path }: { path: string }) {
  const parts = path.split("/").filter(Boolean);
  const leaf = parts.at(-1) ?? path;
  const parent = parts.slice(0, -1).join("/");
  return (
    <div className="min-w-0">
      <div className="truncate font-medium">{leaf}</div>
      <div className="truncate font-mono text-[11px] text-muted-foreground">
        /{parent}
      </div>
    </div>
  );
}

function FilterChip({
  active,
  label,
  onClick,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <Button
      size="sm"
      variant={active ? "default" : "outline"}
      onClick={onClick}
    >
      {label}
    </Button>
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

function EmptyCleanup({ filter }: { filter: KindFilter }) {
  return (
    <div className="rounded-xl border border-dashed bg-card/40 px-4 py-10 text-center">
      <p className="text-sm font-medium">No leftovers in this filter</p>
      <p className="mt-1 text-sm text-muted-foreground">
        {filter === "all"
          ? "Nothing matched investigation leftovers or used media. nightshift and ai-memory were never candidates."
          : "This slice is empty. Clear the filter to see the rest."}
      </p>
    </div>
  );
}
