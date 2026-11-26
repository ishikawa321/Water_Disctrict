import Image from "next/image";
import { RefreshCw } from "lucide-react";
import type { ReactNode } from "react";
export function BrandedState({
  error,
  children,
}: {
  error?: string;
  children?: ReactNode;
}) {
  return (
    <section
      className="branded-state water-surface"
      aria-label={error ? "Workspace unavailable" : "Loading workspace"}
    >
      <Image
        src="/brand/logo.png"
        alt="Maramag Water District logo"
        width={96}
        height={96}
      />
      <h1>
        Water District
        <br />
        Connect
      </h1>
      <p>Maramag, Philippines</p>
      {error ? (
        <p role="alert">{error}</p>
      ) : (
        <div className="branded-progress" role="status">
          <RefreshCw className="spin" size={24} />
          <span>Preparing your water-service app…</span>
        </div>
      )}
      {children}
    </section>
  );
}
