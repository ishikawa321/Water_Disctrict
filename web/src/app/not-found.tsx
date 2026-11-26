import Link from "next/link";
import { Card } from "@/components/ui";
export default function NotFound() {
  return (
    <main className="blank-state">
      <Card title="Page not found">
        <p>This page is unavailable.</p>
        <Link className="button" style={{ marginTop: 20 }} href="/">
          Return to your workspace
        </Link>
      </Card>
    </main>
  );
}
