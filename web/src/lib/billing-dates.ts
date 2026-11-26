import { todayInManila } from "./format";
export function nextBillingDueDate(today = todayInManila()) {
  const issue = new Date(`${today}T00:00:00Z`);
  issue.setUTCDate(issue.getUTCDate() + 3);
  return issue.toISOString().slice(0, 10);
}
