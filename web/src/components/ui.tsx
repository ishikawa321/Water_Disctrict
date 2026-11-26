import { Inbox, RefreshCw } from 'lucide-react';
import Image from 'next/image';
import type { ReactNode } from 'react';
export function Brand() { return <div className="brand"><Image src="/brand/logo.png" width={46} height={46} alt="Maramag Water District logo" /><span>Maramag Water District<small>WATER DISTRICT CONNECT</small></span></div>; }
export function Badge({ children }: { children: ReactNode }) {
  const text = String(children);
  const tone = ['Resolved', 'Active', 'Verified', 'Published', 'Paid'].includes(text) ? 'green' : ['Under review', 'Assigned', 'In progress'].includes(text) ? 'blue' : ['Overdue', 'Service interruption', 'Inactive'].includes(text) ? 'red' : 'amber';
  return <span className={`badge ${tone}`}><span aria-hidden="true">●</span>{children}</span>;
}
export function Empty({ title = 'No records yet', children }: { title?: string; children?: ReactNode }) { return <div className="empty"><Inbox size={30} strokeWidth={1.5} /><h3>{title}</h3><p>{children ?? 'Saved records will appear here after refresh.'}</p></div>; }
export function Loading() { return <div className="loading" role="status"><RefreshCw className="spin" size={20} /> Loading saved records…</div>; }
export function Feedback({ error, success }: { error?: string | null; success?: string | null }) { return <>{error && <div className="feedback error" role="alert">{error}</div>}{success && <div className="feedback success" role="status">{success}</div>}</>; }
export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) { return <label className="field"><span>{label}</span>{children}{hint && <small>{hint}</small>}</label>; }
export function Card({ title, children, className = '' }: { title?: string; children: ReactNode; className?: string }) { return <section className={`card ${className}`}>{title && <h2>{title}</h2>}{children}</section>; }
