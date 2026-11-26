"use client";
import { useState, type FormEvent } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { save } from "@/lib/client";
import { useDraft, useResource } from "@/lib/hooks";
import {
  dateLabel,
  money,
  positiveMoney,
  dateOnly,
  todayInManila,
} from "@/lib/format";
import { interruptionPrefix, noticeTitle } from "@/lib/policy";
import type {
  ClientRegistration,
  Account,
  Bill,
  Notice,
  Payment,
  StaffMember,
} from "@/lib/types";
import { Badge, Card, Empty, Feedback, Field } from "./ui";
import { DataState, PageHeader, Refresh, useMutation } from "./data-ui";
import { PaymentTable } from "./payment-table";
import { MonthlyBilling } from "./monthly-billing";
import { nextBillingDueDate } from "@/lib/billing-dates";

export function AccountsPage() {
  const records = useResource<Account[]>("/api/office/office/accounts", 30_000);
  const pending = useResource<ClientRegistration[]>(
    "/api/office/office/registrations",
    30_000,
  );
  const mutation = useMutation();
  const [approvedNumber, setApprovedNumber] = useState("");
  function approve(id: string) {
    void mutation.run(async () => {
      const result = await save<{ accountNumber: string }>(
        `/api/office/office/registrations/${id}/approve`,
        {},
      );
      if (!result.accountNumber)
        throw new Error(
          "Approval could not be confirmed. Refresh before retrying.",
        );
      setApprovedNumber(result.accountNumber);
      void records.reload();
      void pending.reload();
    }, "Registration approved. The account number has been assigned. The client can sign in after email confirmation.");
  }
  const [search, setSearch] = useState("");
  const visible =
    records.data?.filter((r) =>
      `${r.accountNumber} ${r.holderName} ${r.serviceAddress}`
        .toLowerCase()
        .includes(search.toLowerCase()),
    ) ?? [];
  return (
    <>
      <PageHeader
        title="Service accounts"
        subtitle="Review pending registrations. Approval assigns the next service account number."
      >
        <Refresh
          onClick={() => {
            void records.reload();
            void pending.reload();
          }}
          busy={records.busy || pending.busy}
        />
      </PageHeader>
      <Feedback
        error={mutation.error}
        success={
          mutation.success && approvedNumber
            ? `Registration approved. Service account ${approvedNumber} assigned. The client can sign in after email confirmation.`
            : mutation.success
        }
      />
      <Card title="Pending registrations">
        <DataState {...pending} loaded={!!pending.data}>
          {pending.data?.length === 0 && <p>No pending registrations.</p>}
          {pending.data?.map((r) => (
            <div className="toolbar" key={r.userId}>
              <div>
                <strong>{r.fullName}</strong>
                <p>{r.email}</p>
                <p>{r.serviceAddress}</p>
                <small>
                  {r.emailConfirmedAt
                    ? "Email confirmed"
                    : "Email confirmation pending"}
                </small>
              </div>
              <button
                className="primary"
                disabled={mutation.busy}
                onClick={() => approve(r.userId)}
              >
                Approve registration
              </button>
            </div>
          ))}
        </DataState>
      </Card>
      <Card>
        <div className="toolbar">
          <input
            className="search-input"
            aria-label="Search loaded accounts"
            placeholder="Search account number, holder or address"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <DataState
          {...records}
          loaded={!!records.data}
          empty={!!records.data && !visible.length}
        >
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Account number</th>
                  <th>Account holder</th>
                  <th>Service address</th>
                  <th>State</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((r) => (
                  <tr key={r.id}>
                    <td>{r.accountNumber}</td>
                    <td>{r.holderName}</td>
                    <td>{r.serviceAddress}</td>
                    <td>
                      <Badge>{r.active ? "Active" : "Inactive"}</Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </DataState>
        <p className="list-meta">
          {visible.length} shown · Up to 1,000 accounts. Search filters the
          loaded list.
        </p>
      </Card>
    </>
  );
}

export function BillsPage() {
  const records = useResource<Bill[]>("/api/office/office/bills");
  const accounts = useResource<Account[]>("/api/office/office/accounts");
  const [show, setShow] = useState(false);
  const [search, setSearch] = useState("");
  const [draft, setDraft] = useDraft("office:add-bill", {
    accountId: "",
    requestId: crypto.randomUUID(),
    dueDate: nextBillingDueDate(),
    amountDue: "",
  });
  const mutation = useMutation();
  const visible =
    records.data?.filter((r) =>
      `${r.billNumber} ${r.accountNumber}`
        .toLowerCase()
        .includes(search.toLowerCase()),
    ) ?? [];
  function submit(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      const amountDue = positiveMoney(draft.amountDue);
      dateOnly(draft.dueDate);
      await save("/api/office/office/bills", { ...draft, amountDue });
      setDraft({ ...draft, requestId: crypto.randomUUID(), amountDue: "" });
      void records.reload();
    }, "Billing record created.");
  }
  return (
    <>
      <PageHeader
        title="Billing records"
        subtitle="District-computed charges and verified remaining balances."
      >
        <Refresh
          onClick={() => {
            void records.reload();
            void accounts.reload();
          }}
          busy={records.busy || accounts.busy}
        />
        <button className="primary" onClick={() => setShow(!show)}>
          <Plus size={16} />
          {show ? "Close form" : "New bill"}
        </button>
      </PageHeader>
      <Feedback error={mutation.error} success={mutation.success} />
      {show && (
        <Card title="Create a billing record">
          <Feedback error={accounts.error} />
          <form className="form" onSubmit={submit}>
            <fieldset disabled={mutation.busy}>
              <Field
                label="Active service account"
                hint="Up to 1,000 loaded accounts. Refresh if an account was recently created."
              >
                <select
                  required
                  value={draft.accountId}
                  onChange={(e) =>
                    setDraft({ ...draft, accountId: e.target.value })
                  }
                >
                  <option value="">Select an active account</option>
                  {accounts.data
                    ?.filter((a) => a.active)
                    .map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.accountNumber} / {a.holderName}
                      </option>
                    ))}
                </select>
              </Field>
              <p>A unique bill number is generated when this bill is saved.</p>
              <Field label="District-computed amount (PHP)">
                <input
                  inputMode="decimal"
                  value={draft.amountDue}
                  onChange={(e) =>
                    setDraft({ ...draft, amountDue: e.target.value })
                  }
                  placeholder="0.00"
                  required
                />
              </Field>
              <Field label="Due date">
                <input
                  type="date"
                  min={todayInManila()}
                  max="2100-12-31"
                  value={draft.dueDate}
                  onChange={(e) =>
                    setDraft({ ...draft, dueDate: e.target.value })
                  }
                  required
                />
              </Field>
              <button className="primary" type="submit">
                {mutation.busy ? "Saving…" : "Create bill"}
              </button>
            </fieldset>
            <small>
              Enter the amount computed by the district. This form does not
              calculate tariffs.
            </small>
          </form>
        </Card>
      )}
      <MonthlyBilling accounts={accounts.data ?? []} />
      <Card>
        <div className="toolbar">
          <input
            className="search-input"
            aria-label="Search loaded bills"
            placeholder="Search bill or account number"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <DataState
          {...records}
          loaded={!!records.data}
          empty={!!records.data && !visible.length}
        >
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Bill / account</th>
                  <th>Due</th>
                  <th>Original</th>
                  <th>Interest</th>
                  <th>Total</th>
                  <th>Verified paid</th>
                  <th>Remaining</th>
                  <th>History</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((b) => (
                  <tr key={b.id}>
                    <td>
                      {b.billNumber}
                      <small>{b.accountNumber}</small>
                    </td>
                    <td>{dateLabel(b.dueDate)}</td>
                    <td className="amount">
                      {money(b.baseAmount ?? b.amountDue)}
                    </td>
                    <td className="amount">
                      {money(b.interestAmount ?? 0)}
                      <small>{b.interestDays ?? 0} days</small>
                    </td>
                    <td className="amount">{money(b.amountDue)}</td>
                    <td className="amount">{money(b.paid)}</td>
                    <td className="amount">{money(b.remaining)}</td>
                    <td>
                      <Link href={`/office/payments?billId=${b.id}`}>
                        Payments
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </DataState>
        <p className="list-meta">
          Up to 1,000 bills, most recent due dates first. Search filters loaded
          records.
        </p>
      </Card>
    </>
  );
}

export function PaymentsPage({
  initialBillId = "",
}: {
  initialBillId?: string;
}) {
  const bills = useResource<Bill[]>("/api/office/office/bills");
  const [filter, setFilter] = useState(initialBillId);
  const records = useResource<Payment[]>(
    `/api/office/office/payments${filter ? `?billId=${encodeURIComponent(filter)}` : ""}`,
  );
  const [show, setShow] = useState(false);
  const [draft, setDraft] = useDraft("office:add-payment", {
    billId: initialBillId,
    requestId: crypto.randomUUID(),
    paymentDate: todayInManila(),
    amountPaid: "",
    verified: false,
  });
  const mutation = useMutation();
  const [confirmedReference, setConfirmedReference] = useState("");
  function submit(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      const amountPaid = positiveMoney(draft.amountPaid);
      dateOnly(draft.paymentDate);
      if (draft.paymentDate > todayInManila())
        throw new Error("The payment date cannot be in the future.");
      if (!draft.verified)
        throw new Error("Confirm verification against district records.");
      const confirmed = await save<Payment>("/api/office/office/payments", {
        ...draft,
        amountPaid,
      });
      setConfirmedReference(confirmed.receiptReference);
      setDraft({
        ...draft,
        requestId: crypto.randomUUID(),
        amountPaid: "",
        verified: false,
      });
      void records.reload();
      void bills.reload();
    }, "Verified offline payment recorded.");
  }
  return (
    <>
      <PageHeader
        title="Verified payments"
        subtitle="A clear record of payments verified against district records."
      >
        <Refresh
          onClick={() => {
            void records.reload();
            void bills.reload();
          }}
          busy={records.busy || bills.busy}
        />
        <button className="primary" onClick={() => setShow(!show)}>
          <Plus size={16} />
          {show ? "Close form" : "Record payment"}
        </button>
      </PageHeader>
      <Feedback error={mutation.error} success={mutation.success} />
      {confirmedReference && (
        <p role="status" className="feedback success">
          Payment confirmed. Reference: <strong>{confirmedReference}</strong>
        </p>
      )}
      {show && (
        <Card title="Record a verified offline payment">
          <Feedback error={bills.error} />
          <form className="form" onSubmit={submit}>
            <fieldset disabled={mutation.busy}>
              <Field label="Bill">
                <select
                  required
                  value={draft.billId}
                  onChange={(e) =>
                    setDraft({ ...draft, billId: e.target.value })
                  }
                >
                  <option value="">Select a bill</option>
                  {bills.data?.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.billNumber} / {b.accountNumber} / {money(b.remaining)}{" "}
                      remaining
                    </option>
                  ))}
                </select>
              </Field>
              <p>
                A unique 10-digit reference is generated after confirmation.
              </p>
              <button
                type="button"
                className="secondary"
                disabled={!draft.billId}
                onClick={() => {
                  const bill = bills.data?.find((b) => b.id === draft.billId);
                  if (bill)
                    setDraft({ ...draft, amountPaid: String(bill.remaining) });
                }}
              >
                Use full remaining balance
              </button>
              <div className="form-row">
                <Field label="Payment date">
                  <input
                    type="date"
                    min="2000-01-01"
                    max={todayInManila()}
                    value={draft.paymentDate}
                    onChange={(e) =>
                      setDraft({ ...draft, paymentDate: e.target.value })
                    }
                    required
                  />
                </Field>
                <Field label="Verified amount (PHP)">
                  <input
                    inputMode="decimal"
                    value={draft.amountPaid}
                    onChange={(e) =>
                      setDraft({ ...draft, amountPaid: e.target.value })
                    }
                    required
                    placeholder="0.00"
                  />
                </Field>
              </div>
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked={draft.verified}
                  onChange={(e) =>
                    setDraft({ ...draft, verified: e.target.checked })
                  }
                  required
                />
                <span>
                  I have verified this offline payment against district records.
                </span>
              </label>
              <button className="primary" type="submit">
                {mutation.busy ? "Saving…" : "Confirm payment"}
              </button>
            </fieldset>
            <small>
              Verification identity and time are recorded by the shared service.
            </small>
          </form>
        </Card>
      )}
      <Card>
        <Feedback error={bills.error} />
        <div className="toolbar">
          <label className="field" style={{ width: "100%" }}>
            <span>Payment history</span>
            <select value={filter} onChange={(e) => setFilter(e.target.value)}>
              <option value="">All loaded history</option>
              {filter && !bills.data?.some((b) => b.id === filter) && (
                <option value={filter}>Selected bill</option>
              )}
              {bills.data?.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.billNumber} / {b.accountNumber}
                </option>
              ))}
            </select>
          </label>
        </div>
        <DataState
          {...records}
          loaded={!!records.data}
          empty={records.data?.length === 0}
        >
          {records.data && <PaymentTable payments={records.data} />}
        </DataState>
        <p className="list-meta">
          Up to 1,000 payments
          {filter ? " for the selected bill" : ", newest first"}. These are
          verified offline records.
        </p>
      </Card>
    </>
  );
}

export function AnnouncementEditor() {
  const records = useResource<Notice[]>("/api/office/office/announcements");
  const [selected, setSelected] = useState<Notice | null>(null);
  const [show, setShow] = useState(false);
  const [savedMessage, setSavedMessage] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  return (
    <>
      <PageHeader
        title="Announcements"
        subtitle="Keep consumers informed with district news and service notices."
      >
        <Refresh onClick={records.reload} busy={records.busy || saving} />
        <button
          className="primary"
          disabled={saving}
          onClick={() => {
            setSelected(null);
            setShow(true);
          }}
        >
          <Plus size={16} />
          New notice
        </button>
      </PageHeader>
      <Feedback success={savedMessage} />
      <div className="split">
        <Card title="District notices">
          <DataState
            {...records}
            loaded={!!records.data}
            empty={records.data?.length === 0}
          >
            <div className="record-list">
              {records.data?.map((n) => (
                <button
                  key={n.id}
                  disabled={saving}
                  className={`record-button ${selected?.id === n.id ? "selected" : ""}`}
                  onClick={() => {
                    setSelected(n);
                    setShow(true);
                  }}
                >
                  <div className="row spread">
                    <Badge>{n.published ? "Published" : "Draft"}</Badge>
                    {n.title.startsWith(interruptionPrefix) && (
                      <Badge>Service interruption</Badge>
                    )}
                  </div>
                  <h3>{noticeTitle(n.title)}</h3>
                  <p>{dateLabel(n.updatedAt)}</p>
                </button>
              ))}
            </div>
          </DataState>
          <p className="list-meta">
            Up to 1,000 notices, most recently updated first.
          </p>
        </Card>
        {show ? (
          <NoticeForm
            key={selected?.id ?? "new"}
            notice={selected}
            onClose={() => setShow(false)}
            onBusy={setSaving}
            onSave={(saved) => {
              setSelected(saved);
              setSavedMessage(
                saved.published
                  ? "Published notice saved."
                  : "Draft saved. Consumers cannot see this draft.",
              );
              void records.reload();
            }}
          />
        ) : (
          <Card>
            <Empty title="Choose a notice">
              Select a saved notice to edit, or create a new draft.
            </Empty>
          </Card>
        )}
      </div>
    </>
  );
}
function NoticeForm({
  notice,
  onClose,
  onSave,
  onBusy,
}: {
  notice: Notice | null;
  onClose: () => void;
  onSave: (saved: Notice) => void;
  onBusy: (busy: boolean) => void;
}) {
  const [draft, setDraft] = useDraft(`notice:${notice?.id ?? "new"}`, {
    savedId: notice?.id ?? null,
    title: notice ? noticeTitle(notice.title) : "",
    message: notice?.message ?? "",
    published: notice?.published ?? false,
    isInterruption: notice?.title.startsWith(interruptionPrefix) ?? false,
  });
  const savedId = draft.savedId;
  const mutation = useMutation();
  const limit = 150 - (draft.isInterruption ? interruptionPrefix.length : 0);
  function submit(event: FormEvent) {
    event.preventDefault();
    onBusy(true);
    void mutation
      .run(
        async () => {
          if (draft.title.trim().length > limit)
            throw new Error(
              `The title must fit ${limit} characters including the interruption setting.`,
            );
          const saved = await save<Notice>(
            `/api/office/office/announcements${savedId ? `/${savedId}` : ""}`,
            draft,
            savedId ? "PUT" : "POST",
          );
          setDraft(
            notice
              ? { ...draft, savedId: saved.id }
              : {
                  savedId: null,
                  title: "",
                  message: "",
                  published: false,
                  isInterruption: false,
                },
          );
          onSave(saved);
        },
        draft.published
          ? "Published notice saved."
          : "Draft saved. Consumers cannot see this draft.",
      )
      .finally(() => onBusy(false));
  }
  return (
    <Card title={savedId ? "Edit notice" : "New district notice"}>
      <Feedback error={mutation.error} success={mutation.success} />
      <form className="form" onSubmit={submit}>
        <fieldset disabled={mutation.busy}>
          <Field
            label="Title"
            hint={`${draft.title.length} / ${limit} characters available`}
          >
            <input
              value={draft.title}
              onChange={(e) => setDraft({ ...draft, title: e.target.value })}
              maxLength={150}
              required
            />
          </Field>
          <Field label="Message">
            <textarea
              value={draft.message}
              onChange={(e) => setDraft({ ...draft, message: e.target.value })}
              maxLength={5000}
              required
              rows={7}
            />
          </Field>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={draft.isInterruption}
              onChange={(e) =>
                setDraft({ ...draft, isInterruption: e.target.checked })
              }
            />
            Service interruption notice
          </label>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={draft.published}
              onChange={(e) =>
                setDraft({ ...draft, published: e.target.checked })
              }
            />
            Published — visible to consumers
          </label>
          <div className="row wrap">
            <button className="primary" type="submit">
              {mutation.busy ? "Saving…" : "Save notice"}
            </button>
            <button className="secondary" type="button" onClick={onClose}>
              Close editor
            </button>
          </div>
        </fieldset>
        <small>
          Closing keeps your unsaved draft in this signed-in session.
        </small>
      </form>
    </Card>
  );
}
export function StaffDirectory() {
  const records = useResource<StaffMember[]>("/api/office/admin/staff");
  return (
    <>
      <PageHeader
        title="Staff directory"
        subtitle="Authorized, active office personnel."
      >
        <Refresh onClick={records.reload} busy={records.busy} />
      </PageHeader>
      <Card>
        <DataState
          {...records}
          loaded={!!records.data}
          empty={records.data?.length === 0}
        >
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Role</th>
                  <th>Access</th>
                </tr>
              </thead>
              <tbody>
                {records.data?.map((p) => (
                  <tr key={p.userId}>
                    <td>{p.displayName}</td>
                    <td style={{ textTransform: "capitalize" }}>{p.role}</td>
                    <td>
                      <Badge>Active</Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </DataState>
        <p className="list-meta">
          Read-only directory. Staff accounts are provisioned by an authorized
          operator.
        </p>
      </Card>
    </>
  );
}
