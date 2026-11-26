"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  FileText,
  MessageSquare,
  UserRound,
  Wrench,
  Users,
} from "lucide-react";
import type { Role } from "@/lib/types";
export function MobileDock({ role }: { role: Role }) {
  const pathname = usePathname();
  const base = role === "client" ? "/portal" : "/office";
  const items =
    role === "client"
      ? [
          { path: "", label: "Home", Icon: LayoutDashboard },
          { path: "/bills", label: "Bills", Icon: FileText },
          { path: "/concerns", label: "Requests", Icon: MessageSquare },
          { path: "/profile", label: "Account", Icon: UserRound },
        ]
      : [
          { path: "", label: "Home", Icon: LayoutDashboard },
          ...(role === "admin"
            ? [{ path: "/accounts", label: "Accounts", Icon: Users }]
            : []),
          { path: "/concerns", label: "Concerns", Icon: MessageSquare },
          { path: "/repairs", label: "Repairs", Icon: Wrench },
        ];
  return (
    <nav className="mobile-dock" aria-label="Quick navigation">
      {items.map(({ path, label, Icon }) => {
        const active = path ? pathname === base + path : pathname === base;
        return (
          <Link
            key={path}
            href={base + path}
            aria-current={active ? "page" : undefined}
          >
            <Icon size={20} />
            <span>{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
