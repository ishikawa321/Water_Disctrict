"use client";
import { Card } from "@/components/ui";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main className="blank-state">
      <Card title="The workspace could not be loaded">
        <p>
          Your access or the data service could not be checked. Please retry.
        </p>
        <button className="primary" onClick={reset} style={{ marginTop: 20 }}>
          Try again
        </button>
      </Card>
    </main>
  );
}
