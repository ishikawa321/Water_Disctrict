"use client";
import { useRef, useState, type ReactNode } from "react";
import { RefreshCw, ArrowLeft, ArrowRight } from "lucide-react";
import { message } from "@/lib/client";
import { Empty, Feedback, Loading } from "./ui";
export function PageHeader({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children?: ReactNode;
}) {
  return (
    <div className="page-header">
      <div>
        <div className="eyebrow">Maramag Water District</div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <div className="row wrap">{children}</div>
    </div>
  );
}
export function Refresh({
  onClick,
  busy,
}: {
  onClick: () => void;
  busy?: boolean;
}) {
  return (
    <button className="secondary" onClick={onClick} disabled={busy}>
      <RefreshCw className={busy ? "spin" : ""} size={16} />
      {busy ? "Refreshing…" : "Refresh"}
    </button>
  );
}
export function DataState({
  busy,
  error,
  empty,
  loaded = true,
  children,
}: {
  busy: boolean;
  error: string | null;
  empty?: boolean;
  loaded?: boolean;
  children: ReactNode;
}) {
  return (
    <>
      <Feedback error={error} />
      {busy && !loaded ? (
        <Loading />
      ) : !loaded && error ? (
        <Empty title="Records unavailable">Use Refresh to retry.</Empty>
      ) : empty ? (
        <Empty />
      ) : (
        children
      )}
      {busy && loaded && (
        <p className="list-meta" role="status">
          Refreshing saved records…
        </p>
      )}
    </>
  );
}
export function Pager({
  page,
  hasMore,
  onPage,
  busy,
}: {
  page: number;
  hasMore: boolean;
  onPage: (page: number) => void;
  busy: boolean;
}) {
  if (!page && !hasMore) return null;
  return (
    <div className="pagination">
      <button
        className="secondary"
        disabled={!page || busy}
        onClick={() => onPage(page - 1)}
      >
        <ArrowLeft size={15} /> Previous
      </button>
      <small>Page {page + 1}</small>
      <button
        className="secondary"
        disabled={!hasMore || busy}
        onClick={() => onPage(page + 1)}
      >
        Next <ArrowRight size={15} />
      </button>
    </div>
  );
}
export function useMutation() {
  const lock = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  async function run(
    action: () => Promise<void>,
    confirmed = "Saved and confirmed by the district service.",
  ) {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setError(null);
    setSuccess(null);
    try {
      await action();
      setSuccess(confirmed);
    } catch (error) {
      setError(message(error));
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  return {
    busy,
    error,
    success,
    run,
    clear: () => {
      setError(null);
      setSuccess(null);
    },
  };
}
