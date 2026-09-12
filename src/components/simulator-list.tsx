"use client";

import { useState } from "react";
import { Smartphone } from "lucide-react";

import { ConfirmAction } from "@/components/confirm-action";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import type { SimulatorDevice } from "@/lib/types";

export function SimulatorList({
  simulators,
  pending,
  onClose,
}: {
  simulators: SimulatorDevice[];
  pending: boolean;
  onClose: (udid: string) => Promise<void>;
}) {
  const [confirmUdid, setConfirmUdid] = useState<string | null>(null);
  const confirmDevice =
    simulators.find((device) => device.udid === confirmUdid) ?? null;

  return (
    <section className="rounded-xl bg-card p-4 ring-1 ring-foreground/10">
      <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Smartphone className="size-4" />
            <h2 className="text-sm font-medium">Xcode Simulators</h2>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            List only by default. Close is an explicit later action. Booted
            devices are treated as in use by models and stay up.
          </p>
        </div>
        <Badge variant="outline" className="rounded-md">
          {simulators.filter((device) => device.state === "Booted").length} booted
        </Badge>
      </div>

      {simulators.length === 0 ? (
        <p className="mt-4 text-sm text-muted-foreground">
          No simulators reported. On a Mac this comes from `xcrun simctl list`.
        </p>
      ) : (
        <ul className="mt-4 divide-y">
          {simulators.map((device) => {
            const closeLocked =
              device.inUseByModels || device.state !== "Booted";
            return (
              <li
                key={device.udid}
                className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between"
              >
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{device.name}</span>
                    <Badge variant="secondary" className="rounded-md">
                      {device.runtime}
                    </Badge>
                    <Badge variant="outline" className="rounded-md">
                      {device.state}
                    </Badge>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {device.note}
                  </p>
                  <p className="font-mono text-[11px] text-muted-foreground">
                    {device.udid}
                  </p>
                </div>
                {closeLocked ? (
                  <Tooltip>
                    <TooltipTrigger
                      render={
                        <span className="inline-flex">
                          <Button size="sm" variant="outline" disabled>
                            Close
                          </Button>
                        </span>
                      }
                    />
                    <TooltipContent>
                      {device.inUseByModels
                        ? "Models are using this simulator."
                        : "Already shut down."}
                    </TooltipContent>
                  </Tooltip>
                ) : (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => setConfirmUdid(device.udid)}
                  >
                    Close
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      )}

      <ConfirmAction
        open={confirmUdid !== null}
        title="Close this simulator?"
        description={
          confirmDevice
            ? `${confirmDevice.name} is booted and not marked in use by models. This still will not run unless you confirm.`
            : "Nothing selected."
        }
        confirmLabel="Close simulator"
        pending={pending}
        onOpenChange={(open) => {
          if (!open) setConfirmUdid(null);
        }}
        onConfirm={async () => {
          if (!confirmUdid) return;
          await onClose(confirmUdid);
          setConfirmUdid(null);
        }}
      />
    </section>
  );
}
