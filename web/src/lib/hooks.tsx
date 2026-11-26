"use client";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { api, message } from "./client";
export function useResource<T>(url: string | null, refreshMilliseconds = 0) {
  const [state, setState] = useState<{
    url: string | null;
    data: T | null;
    error: string | null;
    busy: boolean;
  }>({ url, data: null, error: null, busy: !!url });
  const sequence = useRef(0);
  const invalidate = useCallback(() => {
    sequence.current += 1;
  }, []);
  const reload = useCallback(async () => {
    const requestedUrl = url;
    if (!requestedUrl) return;
    const request = ++sequence.current;
    setState((previous) => ({
      url,
      data: previous.url === url ? previous.data : null,
      error: null,
      busy: true,
    }));
    try {
      const next = await api<T>(requestedUrl);
      if (request === sequence.current)
        setState({ url, data: next, error: null, busy: false });
    } catch (error) {
      if (request === sequence.current)
        setState((previous) => ({
          ...previous,
          error: message(error),
          busy: false,
        }));
    }
  }, [url]);
  useEffect(() => {
    const timer = setTimeout(() => {
      void reload();
    }, 0);
    return () => {
      clearTimeout(timer);
      invalidate();
    };
  }, [reload, invalidate]);
  useEffect(() => {
    if (!refreshMilliseconds) return;
    const refresh = () => {
      if (document.visibilityState === "visible") void reload();
    };
    const timer = setInterval(refresh, refreshMilliseconds);
    window.addEventListener("focus", refresh);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", refresh);
    };
  }, [reload, refreshMilliseconds]);
  const setData = useCallback(
    (data: T) => setState((previous) => ({ ...previous, url, data })),
    [url],
  );
  return {
    data: state.url === url ? state.data : null,
    error: state.url === url ? state.error : null,
    busy: state.url === url ? state.busy : !!url,
    reload,
    setData,
  };
}
const DraftContext = createContext<Map<string, unknown> | null>(null);
export function DraftProvider({
  children,
  drafts,
}: {
  children: ReactNode;
  drafts: Map<string, unknown>;
}) {
  return (
    <DraftContext.Provider value={drafts}>{children}</DraftContext.Provider>
  );
}
export function useDraft<T>(key: string, initial: T | (() => T)) {
  const drafts = useContext(DraftContext);
  const [value, setValue] = useState<T>(
    () =>
      (drafts?.get(key) as T | undefined) ??
      (typeof initial === "function" ? (initial as () => T)() : initial),
  );
  function update(next: T) {
    drafts?.set(key, next);
    setValue(next);
  }
  return [value, update] as const;
}
