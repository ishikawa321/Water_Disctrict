import type { Role } from './types';
export const categories = ['Water supply', 'Billing inquiry', 'Repair request', 'Other'] as const;
export const concernStates = ['Submitted', 'Under review', 'Resolved', 'Closed'] as const;
export const repairStates = ['Open', 'Assigned', 'In progress', 'Resolved'] as const;
export const interruptionPrefix = '[Service interruption] ';
export function isRole(value: unknown): value is Role { return value === 'admin' || value === 'staff' || value === 'client'; }
export function homeFor(role: Role) { return role === 'client' ? '/portal' : '/office'; }
// Display choices only. The ASP.NET API validates every transition and assignment.
export function ticketChoices(current: string): string[] {
  return ({ Open: ['Open', 'Assigned'], Assigned: ['Assigned', 'In progress'], 'In progress': ['In progress', 'Resolved'], Resolved: [] } as Record<string, string[]>)[current] ?? [];
}
export function noticeTitle(title: string) { return title.startsWith(interruptionPrefix) ? title.slice(interruptionPrefix.length) : title; }
export const moduleNames: Record<string, string> = { accounts: 'Service accounts', bills: 'Billing', payments: 'Verified payments', announcements: 'Announcements', concerns: 'Service concerns', repairs: 'Repair tickets', staff: 'Staff directory', profile: 'My account', help: 'Help & guidance' };
export function canVisit(role: Role, section: string): boolean {
  if (!section) return true;
  if (role === 'admin') return ['accounts', 'bills', 'payments', 'announcements', 'concerns', 'repairs', 'staff'].includes(section);
  if (role === 'staff') return ['concerns', 'repairs'].includes(section);
  return ['bills', 'payments', 'announcements', 'concerns', 'repairs', 'profile', 'help'].includes(section);
}
