"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { Plus, Wrench } from "lucide-react";
import { api, save } from "@/lib/client";
import { useDraft, useResource } from "@/lib/hooks";
import {
  categories,
  concernStates,
  repairStates,
  ticketChoices,
} from "@/lib/policy";
import { timeLabel } from "@/lib/format";
import type {
  Account,
  Concern,
  PageResult,
  Profile,
  StaffMember,
  Ticket,
  TicketDetails,
} from "@/lib/types";
import { Badge, Card, Empty, Feedback, Field } from "./ui";
import { DataState, PageHeader, Pager, Refresh, useMutation } from "./data-ui";

function Filters({
  kind,
  onFilter,
  busy,
}: {
  kind: "concern" | "repair";
  onFilter: (query: string) => void;
  busy: boolean;
}) {
  return (
    <form
      className="toolbar"
      onSubmit={(e) => {
        e.preventDefault();
        const form = new FormData(e.currentTarget);
        const query = new URLSearchParams();
        if (form.get("search")) query.set("search", String(form.get("search")));
        if (form.get("status")) query.set("status", String(form.get("status")));
        onFilter(query.toString());
      }}
    >
      <input
        name="search"
        className="search-input"
        aria-label="Search subject or account"
        placeholder="Search subject or account number"
        maxLength={150}
      />
      <select name="status" aria-label="Filter by status">
        <option value="">All statuses</option>
        {(kind === "concern" ? concernStates : repairStates).map((s) => (
          <option key={s}>{s}</option>
        ))}
      </select>
      <button className="secondary" type="submit" disabled={busy}>
        Apply filters
      </button>
    </form>
  );
}

export function ConcernIntake({
  account,
  onClose,
  onSave,
}: {
  account?: Account;
  onClose: () => void;
  onSave: () => void;
}) {
  const consumer = !!account;
  const [accountSearch, setAccountSearch] = useState("");
  const [lookup, setLookup] = useState("");
  const accounts = useResource<Account[]>(
    consumer
      ? null
      : `/api/office/workflow/accounts?search=${encodeURIComponent(lookup)}`,
  );
  const blank = () => ({
    requestId: crypto.randomUUID(),
    accountId: account?.id ?? "",
    category: "Water supply",
    subject: "",
    description: "",
  });
  const [draft, setDraft] = useDraft(
    consumer ? "consumer:concern-intake" : "office:concern-intake",
    blank,
  );
  const mutation = useMutation();
  function submit(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      if (!draft.subject.trim() || !draft.description.trim())
        throw new Error("Enter a subject and description.");
      await save(
        consumer ? "/api/consumer/concerns" : "/api/office/workflow/concerns",
        draft,
      );
      setDraft(blank());
      onSave();
    }, "Concern submitted and confirmed. It is ready for office review.");
  }
  return (
    <Card
      title={consumer ? "Submit a service concern" : "Receive an office report"}
    >
      <Feedback error={mutation.error} success={mutation.success} />
      {!consumer && (
        <>
          <form
            className="toolbar"
            onSubmit={(e) => {
              e.preventDefault();
              setLookup(accountSearch);
              if (lookup === accountSearch) void accounts.reload();
            }}
          >
            <input
              className="search-input"
              aria-label="Find account number or holder name"
              placeholder="Find account number or holder name"
              value={accountSearch}
              onChange={(e) => setAccountSearch(e.target.value)}
            />
            <button className="secondary">Find accounts</button>
          </form>
          <Feedback error={accounts.error} />
        </>
      )}
      <form className="form" onSubmit={submit}>
        <fieldset disabled={mutation.busy}>
          {consumer ? (
            <p>
              Service account <strong>{account.accountNumber}</strong>
            </p>
          ) : (
            <Field
              label="Active service account"
              hint="Up to 200 matching active accounts. Use Find accounts to refine the list."
            >
              <select
                value={draft.accountId}
                onChange={(e) =>
                  setDraft({ ...draft, accountId: e.target.value })
                }
                required
              >
                <option value="">Select an account</option>
                {accounts.data?.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.accountNumber} / {a.holderName}
                  </option>
                ))}
              </select>
            </Field>
          )}
          <Field label="Category">
            <select
              value={draft.category}
              onChange={(e) => setDraft({ ...draft, category: e.target.value })}
            >
              {categories.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </Field>
          <Field label="Subject">
            <input
              value={draft.subject}
              onChange={(e) => setDraft({ ...draft, subject: e.target.value })}
              maxLength={150}
              required
              placeholder="Briefly describe the concern"
            />
          </Field>
          <Field label="Description">
            <textarea
              value={draft.description}
              onChange={(e) =>
                setDraft({ ...draft, description: e.target.value })
              }
              maxLength={3000}
              required
              rows={5}
            />
          </Field>
          <div className="row wrap">
            <button className="primary" type="submit">
              {mutation.busy ? "Submitting…" : "Submit concern"}
            </button>
            <button type="button" className="secondary" onClick={onClose}>
              Close form
            </button>
            <button
              type="button"
              className="text-button"
              onClick={() => setDraft(blank())}
            >
              Clear draft
            </button>
          </div>
        </fieldset>
        <small>
          Closing keeps your draft. If a save is unconfirmed, refresh before
          retrying; retries reuse this report’s request identifier.
        </small>
      </form>
    </Card>
  );
}

export function ConcernsPage({
  profile,
  account,
  initialSelected = "",
}: {
  profile: Profile;
  account?: Account;
  initialSelected?: string;
}) {
  const consumer = profile.role === "client";
  const [filters, setFilters] = useState("");
  const [page, setPage] = useState(0);
  const [selected, setSelected] = useState(initialSelected);
  const [show, setShow] = useState(false);
  const records = useResource<Concern[] | PageResult<Concern>>(
    `${consumer ? "/api/consumer/concerns" : "/api/office/workflow/concerns"}?${filters}&page=${page}`,
  );
  const items = Array.isArray(records.data)
    ? records.data
    : (records.data?.items ?? []);
  return (
    <>
      <PageHeader
        title="Service concerns"
        subtitle={
          consumer
            ? "Your reports, saved office responses and service outcomes."
            : "Listen, review, and keep every report moving."
        }
      >
        <Refresh onClick={records.reload} busy={records.busy} />
        <button
          className="primary"
          onClick={() => setShow(!show)}
          disabled={consumer && !account?.active}
        >
          <Plus size={16} />
          {show
            ? "Close form"
            : consumer
              ? "Submit concern"
              : "New office report"}
        </button>
      </PageHeader>
      {show && (
        <ConcernIntake
          account={account}
          onClose={() => setShow(false)}
          onSave={records.reload}
        />
      )}
      <Filters
        kind="concern"
        busy={records.busy}
        onFilter={(query) => {
          setFilters(query);
          setPage(0);
        }}
      />
      <div className="split">
        <Card title="Saved concerns">
          <DataState
            {...records}
            loaded={!!records.data}
            empty={!!records.data && items.length === 0}
          >
            <div className="record-list">
              {items.map((c) => (
                <button
                  className={`record-button ${selected === c.id ? "selected" : ""}`}
                  key={c.id}
                  onClick={() => setSelected(c.id)}
                >
                  <div className="row spread">
                    <small>{c.accountNumber}</small>
                    <Badge>{c.status}</Badge>
                  </div>
                  <h3>{c.subject}</h3>
                  <p>
                    {c.category} · {timeLabel(c.createdAt)}
                  </p>
                </button>
              ))}
            </div>
          </DataState>
          {consumer && records.data && !Array.isArray(records.data) ? (
            <Pager
              page={page}
              hasMore={records.data.hasMore}
              busy={records.busy}
              onPage={setPage}
            />
          ) : (
            <p className="list-meta">
              Up to 500 most recent matching concerns. Search and filters run on
              the server.
            </p>
          )}
        </Card>
        {selected ? (
          consumer ? (
            <ConsumerConcern key={selected} id={selected} />
          ) : (
            <OfficeConcern
              key={selected}
              id={selected}
              profile={profile}
              onSave={records.reload}
            />
          )
        ) : (
          <Card>
            <Empty title="Select a concern">
              Choose a report to see its saved details and response.
            </Empty>
          </Card>
        )}
      </div>
    </>
  );
}

function ConcernBody({ concern }: { concern: Concern }) {
  return (
    <>
      <div className="row spread wrap">
        <h2 style={{ marginBottom: 0 }}>{concern.subject}</h2>
        <Badge>{concern.status}</Badge>
      </div>
      <dl className="detail-grid">
        <div>
          <dt>Account</dt>
          <dd>{concern.accountNumber}</dd>
        </div>
        <div>
          <dt>Category</dt>
          <dd>{concern.category}</dd>
        </div>
        <div>
          <dt>Received</dt>
          <dd>{timeLabel(concern.createdAt)}</dd>
        </div>
        <div>
          <dt>Account holder</dt>
          <dd>{concern.holderName}</dd>
        </div>
      </dl>
      <p className="prose">{concern.description}</p>
      {concern.response && (
        <>
          <hr />
          <h3>Office response</h3>
          <p className="prose" style={{ marginTop: 10 }}>
            {concern.response}
          </p>
          {concern.reviewedAt && (
            <small>Saved {timeLabel(concern.reviewedAt)}</small>
          )}
        </>
      )}
    </>
  );
}
function ConsumerConcern({ id }: { id: string }) {
  const record = useResource<PageResult<Concern>>(
    `/api/consumer/concerns?id=${encodeURIComponent(id)}`,
  );
  const concern = record.data?.items[0];
  return (
    <Card>
      <Refresh onClick={record.reload} busy={record.busy} />
      <div style={{ marginTop: 20 }}>
        <DataState
          {...record}
          loaded={!!record.data}
          empty={!!record.data && !concern}
        >
          {concern && (
            <>
              <ConcernBody concern={concern} />
              {concern.ticketId && (
                <Link
                  className="button secondary"
                  style={{ marginTop: 20 }}
                  href={`/portal/repairs?ticketId=${concern.ticketId}`}
                >
                  <Wrench size={16} />
                  View related repair
                </Link>
              )}
            </>
          )}
        </DataState>
      </div>
    </Card>
  );
}
function OfficeConcern({
  id,
  profile,
  onSave,
}: {
  id: string;
  profile: Profile;
  onSave: () => void;
}) {
  const record = useResource<Concern>(`/api/office/workflow/concerns/${id}`);
  return (
    <Card>
      <div className="row spread wrap">
        <h2 style={{ marginBottom: 0 }}>Concern detail</h2>
        <Refresh onClick={record.reload} busy={record.busy} />
      </div>
      <div style={{ marginTop: 22 }}>
        <DataState {...record} loaded={!!record.data}>
          {record.data && (
            <>
              <ConcernBody concern={record.data} />
              {record.data.ticketId ? (
                <Link
                  className="button secondary"
                  style={{ marginTop: 20 }}
                  href={`/office/repairs?ticketId=${record.data.ticketId}`}
                >
                  <Wrench size={16} />
                  Open linked repair ticket
                </Link>
              ) : (
                ["Submitted", "Under review"].includes(record.data.status) && (
                  <ReviewForm
                    record={record.data}
                    profile={profile}
                    onSave={() => {
                      void record.reload();
                      onSave();
                    }}
                    onRebase={async () => {
                      const fresh = await api<Concern>(
                        `/api/office/workflow/concerns/${id}`,
                      );
                      record.setData(fresh);
                      return fresh;
                    }}
                  />
                )
              )}
            </>
          )}
        </DataState>
      </div>
    </Card>
  );
}
function ReviewForm({
  record,
  profile,
  onSave,
  onRebase,
}: {
  record: Concern;
  profile: Profile;
  onSave: () => void;
  onRebase: () => Promise<Concern>;
}) {
  const router = useRouter();
  const [draft, setDraft] = useDraft(`review:${record.id}`, {
    version: record.version,
    status: "Under review",
    response: record.response ?? "",
    note: "",
  });
  const [version, setVersion] = useState(draft.version);
  const mutation = useMutation();
  function review(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      const saved = await save<Concern>(
        `/api/office/workflow/concerns/${record.id}/review`,
        { version, status: draft.status, response: draft.response },
        "PUT",
      );
      setVersion(saved.version);
      setDraft({ ...draft, version: saved.version });
      onSave();
    }, "Concern review saved.");
  }
  async function rebase() {
    const fresh = await onRebase();
    setVersion(fresh.version);
    setDraft({ ...draft, version: fresh.version });
  }
  return (
    <>
      <hr />
      <Feedback error={mutation.error} success={mutation.success} />
      {version !== record.version && (
        <div className="feedback info">
          The saved record changed. Review the details above, then reload the
          form version before saving.
        </div>
      )}
      <form className="form" onSubmit={review}>
        <fieldset disabled={mutation.busy}>
          <Field label="Review decision">
            <select
              value={draft.status}
              onChange={(e) => setDraft({ ...draft, status: e.target.value })}
            >
              <option>Under review</option>
              <option>Closed</option>
            </select>
          </Field>
          <Field
            label={
              draft.status === "Closed"
                ? "Closure explanation (required)"
                : "Office response"
            }
          >
            <textarea
              value={draft.response}
              onChange={(e) => setDraft({ ...draft, response: e.target.value })}
              maxLength={3000}
              required={draft.status === "Closed"}
            />
          </Field>
          <div className="row wrap">
            <button className="primary">
              {mutation.busy ? "Saving…" : "Save review"}
            </button>
            <button
              type="button"
              className="secondary"
              onClick={() => {
                void mutation.run(
                  rebase,
                  "Latest form version loaded. Your response draft was retained; review it before saving.",
                );
              }}
            >
              Reload form version
            </button>
          </div>
        </fieldset>
      </form>
      {profile.role === "admin" && record.status === "Under review" && (
        <>
          <hr />
          <h3>Create repair ticket</h3>
          <p style={{ margin: "8px 0 15px" }}>
            Dispatch this reviewed concern into one Open repair ticket.
          </p>
          <form
            className="form"
            onSubmit={(e) => {
              e.preventDefault();
              void mutation.run(async () => {
                const result = await save<TicketDetails>(
                  "/api/office/workflow/tickets",
                  {
                    concernId: record.id,
                    concernVersion: version,
                    note: draft.note,
                  },
                );
                setDraft({ ...draft, note: "" });
                onSave();
                router.push(`/office/repairs?ticketId=${result.ticket.id}`);
              }, "Repair ticket created.");
            }}
          >
            <fieldset disabled={mutation.busy}>
              <Field label="Initial repair note">
                <textarea
                  value={draft.note}
                  onChange={(e) => setDraft({ ...draft, note: e.target.value })}
                  maxLength={3000}
                  required
                />
              </Field>
              <button className="primary">
                {mutation.busy ? "Saving…" : "Create repair ticket"}
              </button>
            </fieldset>
          </form>
        </>
      )}
      <small style={{ display: "block", marginTop: 16 }}>
        Drafts stay in this signed-in session. Linked concern outcomes are
        updated through the repair workflow.
      </small>
    </>
  );
}

export function RepairsPage({
  profile,
  initialSelected = "",
}: {
  profile: Profile;
  initialSelected?: string;
}) {
  const consumer = profile.role === "client";
  const [filters, setFilters] = useState("");
  const [page, setPage] = useState(0);
  const [selected, setSelected] = useState(initialSelected);
  const records = useResource<Ticket[] | PageResult<Ticket>>(
    `${consumer ? "/api/consumer/repairs" : "/api/office/workflow/tickets"}?${filters}&page=${page}`,
  );
  const items = Array.isArray(records.data)
    ? records.data
    : (records.data?.items ?? []);
  return (
    <>
      <PageHeader
        title={profile.role === "staff" ? "Assigned repairs" : "Repair tickets"}
        subtitle={
          consumer
            ? "Progress reflects saved updates from district personnel."
            : "Coordinate repairs with clear assignments, notes and saved history."
        }
      >
        <Refresh onClick={records.reload} busy={records.busy} />
      </PageHeader>
      <Filters
        kind="repair"
        busy={records.busy}
        onFilter={(q) => {
          setFilters(q);
          setPage(0);
        }}
      />
      <div className="split">
        <Card
          title={
            profile.role === "staff"
              ? "Your assigned work"
              : "Saved repair tickets"
          }
        >
          <DataState
            {...records}
            loaded={!!records.data}
            empty={!!records.data && !items.length}
          >
            <div className="record-list">
              {items.map((t) => (
                <button
                  key={t.id}
                  className={`record-button ${selected === t.id ? "selected" : ""}`}
                  onClick={() => setSelected(t.id)}
                >
                  <div className="row spread">
                    <small>{t.accountNumber}</small>
                    <Badge>{t.status}</Badge>
                  </div>
                  <h3>{t.subject}</h3>
                  <p>{t.assignedTo ?? "Awaiting assignment"}</p>
                </button>
              ))}
            </div>
          </DataState>
          {consumer && records.data && !Array.isArray(records.data) ? (
            <Pager
              page={page}
              hasMore={records.data.hasMore}
              busy={records.busy}
              onPage={setPage}
            />
          ) : (
            <p className="list-meta">
              Up to 500 most recent matching tickets. Staff can see only their
              own assigned work.
            </p>
          )}
        </Card>
        {selected ? (
          consumer ? (
            <ConsumerRepair key={selected} id={selected} />
          ) : (
            <OfficeRepair
              key={selected}
              id={selected}
              profile={profile}
              onSave={records.reload}
            />
          )
        ) : (
          <Card>
            <Empty title="Select a repair ticket">
              Choose a saved repair to see its progress.
            </Empty>
          </Card>
        )}
      </div>
    </>
  );
}
function RepairBody({
  ticket,
  consumer,
}: {
  ticket: Ticket;
  consumer: boolean;
}) {
  return (
    <>
      <div className="row spread wrap">
        <h2 style={{ marginBottom: 0 }}>{ticket.subject}</h2>
        <Badge>{ticket.status}</Badge>
      </div>
      <dl className="detail-grid">
        <div>
          <dt>Service account</dt>
          <dd>{ticket.accountNumber}</dd>
        </div>
        <div>
          <dt>Assigned personnel</dt>
          <dd>{ticket.assignedTo ?? "Not yet assigned"}</dd>
        </div>
        <div>
          <dt>Last saved update</dt>
          <dd>{timeLabel(ticket.updatedAt)}</dd>
        </div>
      </dl>
      <div className="repair-stages" aria-label="Current saved repair state">
        {repairStates.map((s) => (
          <span className={ticket.status === s ? "current" : ""} key={s}>
            {s}
            {ticket.status === s ? " · Current" : ""}
          </span>
        ))}
      </div>
      <p className="prose">{ticket.latestUpdate}</p>
      <Link
        className="text-button"
        style={{ display: "inline-block" }}
        href={`/${consumer ? "portal" : "office"}/concerns?concernId=${ticket.concernId}`}
      >
        View linked concern →
      </Link>
    </>
  );
}
function ConsumerRepair({ id }: { id: string }) {
  const record = useResource<PageResult<Ticket>>(
    `/api/consumer/repairs?id=${encodeURIComponent(id)}`,
  );
  const ticket = record.data?.items[0];
  return (
    <Card>
      <Refresh onClick={record.reload} busy={record.busy} />
      <div style={{ marginTop: 22 }}>
        <DataState
          {...record}
          loaded={!!record.data}
          empty={!!record.data && !ticket}
        >
          {ticket && <RepairBody ticket={ticket} consumer />}
        </DataState>
      </div>
    </Card>
  );
}
function OfficeRepair({
  id,
  profile,
  onSave,
}: {
  id: string;
  profile: Profile;
  onSave: () => void;
}) {
  const record = useResource<TicketDetails>(
    `/api/office/workflow/tickets/${id}`,
  );
  const assignees = useResource<StaffMember[]>(
    profile.role === "admin" ? "/api/office/workflow/assignees" : null,
  );
  return (
    <Card>
      <div className="row spread wrap">
        <h2 style={{ marginBottom: 0 }}>Ticket detail & history</h2>
        <Refresh
          onClick={() => {
            void record.reload();
            if (profile.role === "admin") void assignees.reload();
          }}
          busy={record.busy || assignees.busy}
        />
      </div>
      <div style={{ marginTop: 22 }}>
        <DataState {...record} loaded={!!record.data}>
          {record.data && (
            <>
              <RepairBody ticket={record.data.ticket} consumer={false} />
              <hr />
              <h3>Chronological history</h3>
              {record.data.history.length ? (
                <ol className="timeline">
                  {record.data.history.map((h) => (
                    <li key={h.id}>
                      <Badge>{h.status}</Badge>
                      <p>{h.note}</p>
                      <small>
                        {h.changedBy}
                        {h.assignedTo ? ` · Assigned to ${h.assignedTo}` : ""}
                      </small>
                      <small>{timeLabel(h.changedAt)}</small>
                    </li>
                  ))}
                </ol>
              ) : (
                <Empty title="No saved history" />
              )}
              {record.data.ticket.status !== "Resolved" && (
                <>
                  <hr />
                  <TicketUpdate
                    record={record.data}
                    profile={profile}
                    assignees={assignees.data ?? []}
                    assigneeError={assignees.error}
                    onSave={() => {
                      void record.reload();
                      onSave();
                    }}
                  />
                </>
              )}
            </>
          )}
        </DataState>
      </div>
    </Card>
  );
}
function TicketUpdate({
  record,
  profile,
  assignees,
  assigneeError,
  onSave,
}: {
  record: TicketDetails;
  profile: Profile;
  assignees: StaffMember[];
  assigneeError: string | null;
  onSave: () => void;
}) {
  const ticket = record.ticket;
  const [draft, setDraft] = useDraft(`ticket:${ticket.id}`, {
    version: ticket.version,
    status: ticket.status,
    assignedToUserId: ticket.assignedToUserId ?? "",
    note: "",
  });
  const [version, setVersion] = useState(draft.version);
  const mutation = useMutation();
  function submit(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      const saved = await save<TicketDetails>(
        `/api/office/workflow/tickets/${ticket.id}`,
        {
          version,
          status: draft.status,
          assignedToUserId: draft.assignedToUserId || null,
          note: draft.note,
        },
        "PUT",
      );
      setVersion(saved.ticket.version);
      setDraft({
        version: saved.ticket.version,
        status: saved.ticket.status,
        assignedToUserId: saved.ticket.assignedToUserId ?? "",
        note: "",
      });
      onSave();
    }, "Repair update saved with its history event.");
  }
  const allowed = ticketChoices(ticket.status);
  return (
    <>
      <h3>Record an update</h3>
      <Feedback
        error={mutation.error ?? assigneeError}
        success={mutation.success}
      />
      {version !== ticket.version && (
        <div className="feedback info">
          The saved ticket changed. Review it, then reload the form version
          before saving. Your note is retained.
        </div>
      )}
      <form className="form" style={{ marginTop: 16 }} onSubmit={submit}>
        <fieldset disabled={mutation.busy}>
          <Field label="Repair status">
            <select
              value={draft.status}
              onChange={(e) => setDraft({ ...draft, status: e.target.value })}
            >
              {!allowed.includes(draft.status) && (
                <option value={draft.status}>
                  {draft.status} (stale choice)
                </option>
              )}
              {allowed.map((s) => (
                <option key={s}>{s}</option>
              ))}
            </select>
          </Field>
          {profile.role === "admin" ? (
            <Field
              label="Assigned Staff identity"
              hint="Only active Staff identities can be assigned. Use Assigned status when making an assignment."
            >
              <select
                value={draft.assignedToUserId}
                onChange={(e) =>
                  setDraft({ ...draft, assignedToUserId: e.target.value })
                }
                required={draft.status !== "Open"}
              >
                <option value="">Not assigned</option>
                {draft.assignedToUserId &&
                  !assignees.some(
                    (a) => a.userId === draft.assignedToUserId,
                  ) && (
                    <option value={draft.assignedToUserId}>
                      Current assignment — refresh to check availability
                    </option>
                  )}
                {assignees.map((a) => (
                  <option key={a.userId} value={a.userId}>
                    {a.displayName}
                  </option>
                ))}
              </select>
            </Field>
          ) : (
            <p>Assigned to you. Staff cannot reassign tickets.</p>
          )}
          <Field label="Update note (required)">
            <textarea
              value={draft.note}
              onChange={(e) => setDraft({ ...draft, note: e.target.value })}
              maxLength={3000}
              required
              rows={4}
            />
          </Field>
          <div className="row wrap">
            <button className="primary">
              {mutation.busy ? "Saving…" : "Save repair update"}
            </button>
            <button
              type="button"
              className="secondary"
              onClick={() => {
                void mutation.run(async () => {
                  const fresh = await api<TicketDetails>(
                    `/api/office/workflow/tickets/${ticket.id}`,
                  );
                  setVersion(fresh.ticket.version);
                  setDraft({
                    ...draft,
                    version: fresh.ticket.version,
                    status: ticketChoices(fresh.ticket.status).includes(
                      draft.status,
                    )
                      ? draft.status
                      : fresh.ticket.status,
                  });
                  onSave();
                }, "Latest version loaded. Review your retained note and assignment before saving.");
              }}
            >
              Reload form version
            </button>
          </div>
        </fieldset>
      </form>
    </>
  );
}
