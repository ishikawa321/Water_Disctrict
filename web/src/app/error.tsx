"use client";
import { BrandedState } from "@/components/branded-state";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main className="blank-state">
      <BrandedState error="Your access or the data service could not be checked. Please retry.">
        <button className="primary" onClick={reset} style={{ marginTop: 20 }}>
          Try again
        </button>
      </BrandedState>
    </main>
  );
}
