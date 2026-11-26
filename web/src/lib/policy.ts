import type { Role } from "./types";
export const categories = [
  "Water supply",
  "Billing inquiry",
  "Repair request",
  "Other",
] as const;
export const concernStates = [
  "Submitted",
  "Under review",
  "Resolved",
  "Closed",
] as const;
export const repairStates = [
  "Open",
  "Assigned",
  "In progress",
  "Completed",
  "Resolved",
] as const;
export const interruptionPrefix = "[Service interruption] ";
export function relatedOne<T extends object>(value: unknown): T | null {
  const record = Array.isArray(value) ? value[0] : value;
  return record && typeof record === "object" ? (record as T) : null;
}
export function isRole(value: unknown): value is Role {
  return value === "admin" || value === "staff" || value === "client";
}
export function homeFor(role: Role) {
  return role === "client" ? "/portal" : "/office";
}
export const clientRepairStates = [
  "Open",
  "Assigned",
  "In progress",
  "Resolved",
] as const;
export function clientRepairStatus(status: string) {
  return status === "Completed" ? "In progress" : status;
}
// The database independently checks the active caller and saved assignment.
export function ticketChoices(current: string, role: Role = "admin"): string[] {
  if (role === "client") return [];
  return (
    (
      {
        Open: role === "admin" ? ["Open", "Assigned"] : [],
        Assigned: ["Assigned", "In progress", "Resolved"],
        "In progress": ["In progress", "Resolved"],
        Completed: ["In progress", "Resolved"],
        Resolved: [],
      } as Record<string, string[]>
    )[current] ?? []
  );
}
export function noticeTitle(title: string) {
  return title.startsWith(interruptionPrefix)
    ? title.slice(interruptionPrefix.length)
    : title;
}
export const moduleNames: Record<string, string> = {
  accounts: "Service accounts",
  bills: "Billing",
  payments: "Verified payments",
  announcements: "Announcements",
  concerns: "Service concerns",
  repairs: "Repair tickets",
  staff: "Staff directory",
  profile: "My account",
  help: "Help & guidance",
};
export function canVisit(role: Role, section: string): boolean {
  if (!section) return true;
  if (role === "admin")
    return [
      "accounts",
      "bills",
      "payments",
      "announcements",
      "concerns",
      "repairs",
      "staff",
    ].includes(section);
  if (role === "staff")
    return ["concerns", "repairs", "bills", "payments"].includes(section);
  return [
    "bills",
    "payments",
    "announcements",
    "concerns",
    "repairs",
    "profile",
    "help",
  ].includes(section);
}
