import type { Role } from "./types";
const guid = "[0-9a-fA-F-]{36}";
// Only these existing contracts can be forwarded; never accept an arbitrary URL.
export function allowOfficeRequest(role: Role, method: string, path: string) {
  if (role === "client") return false;
  if (
    method === "GET" &&
    (/^workflow\/(accounts|capabilities|concerns|tickets)$/.test(path) ||
      new RegExp(`^workflow/(concerns|tickets)/${guid}$`).test(path))
  )
    return true;
  if (method === "POST" && path === "workflow/concerns") return true;
  if (
    method === "PUT" &&
    (new RegExp(`^workflow/concerns/${guid}/review$`).test(path) ||
      new RegExp(`^workflow/tickets/${guid}$`).test(path))
  )
    return true;
  if (role !== "admin") return false;
  if (
    method === "GET" &&
    (path === "workflow/assignees" ||
      path === "admin/staff" ||
      /^office\/(summary|accounts|registrations|bills|payments|announcements|billing-plans|billing-status)$/.test(
        path,
      ))
  )
    return true;
  if (
    method === "POST" &&
    (new RegExp(`^office/registrations/${guid}/approve$`).test(path) ||
      path === "workflow/tickets" ||
      /^office\/(bills|payments|announcements|billing-plans)$/.test(path))
  )
    return true;
  return (
    method === "PUT" && new RegExp(`^office/announcements/${guid}$`).test(path)
  );
}
