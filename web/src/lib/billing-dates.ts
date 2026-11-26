import { todayInManila } from "./format";
export function nextBillingDueDate(today = todayInManila()) {
  const date = new Date(`${today}T00:00:00Z`);
  const issue = new Date(
    Date.UTC(
      date.getUTCFullYear(),
      date.getUTCMonth() + (date.getUTCDate() > 28 ? 1 : 0),
      28,
    ),
  );
  issue.setUTCDate(issue.getUTCDate() + 3);
  return issue.toISOString().slice(0, 10);
}
