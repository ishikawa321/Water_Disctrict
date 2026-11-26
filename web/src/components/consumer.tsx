"use client";
import { useState, type ReactNode } from "react";
import Link from "next/link";
import {
  Bell,
  CircleHelp,
  Droplets,
  FileText,
  MessageSquare,
  ArrowUpRight,
  Wallet,
  UserRound,
  Wrench,
} from "lucide-react";
import { useResource } from "@/lib/hooks";
import { dateLabel, money, timeLabel } from "@/lib/format";
import { interruptionPrefix, noticeTitle } from "@/lib/policy";
import type {
  Account,
  Bill,
  Concern,
  LinkedAccount,
  Notice,
  PageResult,
  Payment,
  Profile,
} from "@/lib/types";
import { Badge, Card, Empty } from "./ui";
import { DataState, PageHeader, Pager, Refresh } from "./data-ui";
import { PaymentTable } from "./payment-table";
import { ConcernsPage, RepairsPage } from "./workflows";

export function AccountGate({
  children,
}: {
  children: (account: Account) => ReactNode;
}) {
  const record = useResource<LinkedAccount>("/api/consumer/account");
  return (
    <>
      <DataState {...record} loaded={!!record.data}>
        {record.data &&
          (record.data.account ? (
            children(record.data.account)
          ) : (
            <Card>
              <Empty title="Your account is not linked yet">
                Contact authorized district personnel to verify and link your
                service account. You can still read published notices and help.
              </Empty>
              <div className="row wrap">
                <Link className="button secondary" href="/portal/announcements">
                  View announcements
                </Link>
                <Link className="button secondary" href="/portal/help">
                  Account guidance
                </Link>
              </div>
            </Card>
          ))}
      </DataState>
      {!record.data && <Refresh onClick={record.reload} busy={record.busy} />}
    </>
  );
}

export function BillCard({ bill }: { bill: Bill }) {
  return (
    <article className="notice">
      <div className="row spread wrap">
        <div>
          <span className="eyebrow">Bill {bill.billNumber}</span>
          <h3>
            {dateLabel(bill.periodStart)} – {dateLabel(bill.periodEnd)}
          </h3>
        </div>
        <Badge>
          {Number(bill.remaining) <= 0
            ? "Paid"
            : bill.dueDate <
                new Intl.DateTimeFormat("en-CA", {
                  timeZone: "Asia/Manila",
                  year: "numeric",
                  month: "2-digit",
                  day: "2-digit",
                }).format(new Date())
              ? "Overdue"
              : "Unpaid"}
        </Badge>
      </div>
      <p>
        Due {dateLabel(bill.dueDate)} · Account {bill.accountNumber}
      </p>
      <div className="bill-summary">
        <div>
          <small>Original amount</small>
          <strong>{money(bill.amountDue)}</strong>
        </div>
        <div>
          <small>Verified payments</small>
          <strong>{money(bill.paid)}</strong>
        </div>
        <div>
          <small>Remaining balance</small>
          <strong style={{ color: "var(--blue)" }}>
            {money(bill.remaining)}
          </strong>
        </div>
      </div>
      <Link
        className="button secondary"
        href={`/portal/payments?billId=${bill.id}`}
      >
        View payment history <ArrowUpRight size={16} />
      </Link>
    </article>
  );
}
export function ConsumerBills() {
  const [page, setPage] = useState(0);
  const records = useResource<PageResult<Bill>>(
    `/api/consumer/bills?page=${page}`,
  );
  return (
    <>
      <PageHeader
        title="My bills"
        subtitle="Original charges, verified offline payments and remaining balances."
      >
        <Refresh onClick={records.reload} busy={records.busy} />
      </PageHeader>
      <Card>
        <DataState
          {...records}
          loaded={!!records.data}
          empty={records.data?.items.length === 0}
        >
          <div className="stack">
            {records.data?.items.map((b) => (
              <BillCard key={b.id} bill={b} />
            ))}
          </div>
        </DataState>
        {records.data && (
          <Pager
            page={page}
            hasMore={records.data.hasMore}
            busy={records.busy}
            onPage={setPage}
          />
        )}
      </Card>
    </>
  );
}
export function ConsumerPayments({ billId }: { billId: string }) {
  const [page, setPage] = useState(0);
  const records = useResource<PageResult<Payment>>(
    billId
      ? `/api/consumer/payments?billId=${encodeURIComponent(billId)}&page=${page}`
      : null,
  );
  return (
    <>
      <PageHeader
        title="Verified payment history"
        subtitle="Payments verified by district personnel for your selected bill."
      >
        {billId && <Refresh onClick={records.reload} busy={records.busy} />}
      </PageHeader>
      <Card>
        {billId ? (
          <>
            <DataState
              {...records}
              loaded={!!records.data}
              empty={records.data?.items.length === 0}
            >
              {records.data && <PaymentTable payments={records.data.items} />}
            </DataState>
            {records.data && (
              <Pager
                page={page}
                hasMore={records.data.hasMore}
                busy={records.busy}
                onPage={setPage}
              />
            )}
          </>
        ) : (
          <Empty title="Choose a bill to view its payments">
            Open My bills and choose View payment history.
          </Empty>
        )}
        <Link
          className="button secondary"
          style={{ marginTop: 20 }}
          href="/portal/bills"
        >
          Go to my bills
        </Link>
        <p className="list-meta">
          These are saved offline payment records. For payment or receipt
          questions, contact district personnel.
        </p>
      </Card>
    </>
  );
}
export function NoticeCard({ notice }: { notice: Notice }) {
  return (
    <article className="notice">
      {notice.title.startsWith(interruptionPrefix) && (
        <Badge>Service interruption</Badge>
      )}
      <h3>{noticeTitle(notice.title)}</h3>
      <p>{notice.message}</p>
      <small>Updated {timeLabel(notice.updatedAt)}</small>
    </article>
  );
}
export function ConsumerNotices() {
  const [page, setPage] = useState(0);
  const records = useResource<PageResult<Notice>>(
    `/api/consumer/announcements?page=${page}`,
  );
  return (
    <>
      <PageHeader
        title="Announcements"
        subtitle="Published district notices and service interruption updates."
      >
        <Refresh onClick={records.reload} busy={records.busy} />
      </PageHeader>
      <Card>
        <DataState
          {...records}
          loaded={!!records.data}
          empty={records.data?.items.length === 0}
        >
          <div className="stack">
            {records.data?.items.map((n) => (
              <NoticeCard key={n.id} notice={n} />
            ))}
          </div>
        </DataState>
        {records.data && (
          <Pager
            page={page}
            hasMore={records.data.hasMore}
            busy={records.busy}
            onPage={setPage}
          />
        )}
      </Card>
    </>
  );
}
export function ConsumerProfile({ profile }: { profile: Profile }) {
  const records = useResource<LinkedAccount>("/api/consumer/account");
  const a = records.data?.account;
  return (
    <>
      <PageHeader
        title="My account"
        subtitle="Your signed-in identity and authorized service account."
      >
        <Refresh onClick={records.reload} busy={records.busy} />
      </PageHeader>
      <Card title="Profile">
        <dl className="detail-grid">
          <div>
            <dt>Name</dt>
            <dd>{profile.displayName}</dd>
          </div>
          <div>
            <dt>Email</dt>
            <dd>{profile.email}</dd>
          </div>
          <div>
            <dt>Access</dt>
            <dd>Consumer</dd>
          </div>
        </dl>
      </Card>
      <Card title="Linked service account">
        <DataState {...records} loaded={!!records.data}>
          {a ? (
            <>
              <div className="row spread">
                <h3>{a.accountNumber}</h3>
                <Badge>{a.active ? "Active" : "Inactive"}</Badge>
              </div>
              <dl className="detail-grid">
                <div>
                  <dt>Account holder</dt>
                  <dd>{a.holderName}</dd>
                </div>
                <div>
                  <dt>Service address</dt>
                  <dd>{a.serviceAddress}</dd>
                </div>
              </dl>
            </>
          ) : (
            records.data && (
              <Empty title="No active account link">
                Contact authorized district personnel to verify your
                relationship to the account and arrange access.
              </Empty>
            )
          )}
        </DataState>
      </Card>
    </>
  );
}
export function ConsumerHelp() {
  return (
    <>
      <PageHeader
        title="Help & guidance"
        subtitle="Making the most of your district services."
      />
      <div className="stack">
        <Card>
          <div className="row">
            <UserRound size={23} color="var(--blue)" />
            <h2 style={{ margin: 0 }}>Account access</h2>
          </div>
          <p style={{ marginTop: 14 }}>
            Use your existing Water District identity. Account linking and
            profile changes require verification by authorized district
            personnel. An account number alone does not grant access.
          </p>
        </Card>
        <Card>
          <div className="row">
            <Wallet size={23} color="var(--blue)" />
            <h2 style={{ margin: 0 }}>Bills and verified payments</h2>
          </div>
          <p style={{ marginTop: 14 }}>
            My bills shows the original district charge, verified payments,
            remaining balance and due date. Payment history contains offline
            payments recorded after district verification. Contact the office if
            a receipt or balance needs review.
          </p>
          <Link className="text-button" href="/portal/bills">
            View my bills →
          </Link>
        </Card>
        <Card>
          <div className="row">
            <Wrench size={23} color="var(--blue)" />
            <h2 style={{ margin: 0 }}>Concerns and repairs</h2>
          </div>
          <p style={{ marginTop: 14 }}>
            Submit a concern with a clear subject and description. District
            personnel review the report and may create a repair ticket. Repair
            progress reflects saved personnel updates. Refresh to view a new
            response or update.
          </p>
          <Link className="text-button" href="/portal/concerns">
            View my concerns →
          </Link>
        </Card>
        <Card>
          <div className="row">
            <CircleHelp size={23} color="var(--blue)" />
            <h2 style={{ margin: 0 }}>Password recovery</h2>
          </div>
          <p style={{ marginTop: 14 }}>
            Use Forgot password on the sign-in page. Open the newest recovery
            email in the same browser where you requested it. If a link expires,
            request another email.
          </p>
        </Card>
      </div>
    </>
  );
}

export function ConsumerDashboard({ profile }: { profile: Profile }) {
  const account = useResource<LinkedAccount>("/api/consumer/account");
  const bills = useResource<PageResult<Bill>>(
    account.data?.account ? "/api/consumer/bills?page=0" : null,
  );
  const concerns = useResource<PageResult<Concern>>(
    account.data?.account ? "/api/consumer/concerns?page=0" : null,
  );
  const notices = useResource<PageResult<Notice>>(
    "/api/consumer/announcements?page=0",
  );
  const refresh = () => {
    void account.reload();
    void bills.reload();
    void concerns.reload();
    void notices.reload();
  };
  const recentNotices = [...(notices.data?.items.slice(0, 10) ?? [])]
    .sort(
      (a, b) =>
        Number(b.title.startsWith(interruptionPrefix)) -
        Number(a.title.startsWith(interruptionPrefix)),
    )
    .slice(0, 2);
  return (
    <>
      <div className="welcome">
        <div>
          <div className="eyebrow" style={{ color: "var(--blue)" }}>
            Your district. Connected.
          </div>
          <h1>Hello, {profile.displayName.split(" ")[0]}.</h1>
          <p>
            Your water services, a little closer. View your account, follow up
            on a concern, and stay informed.
          </p>
        </div>
        <Droplets className="welcome-icon" size={64} strokeWidth={1.3} />
      </div>
      <div className="page-header">
        <div>
          <h2 style={{ marginBottom: 0 }}>Your services</h2>
          <p>
            {account.data?.account
              ? `Service account ${account.data.account.accountNumber}`
              : "Your connected district account"}
          </p>
        </div>
        <Refresh
          onClick={refresh}
          busy={account.busy || bills.busy || concerns.busy || notices.busy}
        />
      </div>
      <DataState {...account} loaded={!!account.data}>
        {account.data && !account.data.account && (
          <Card>
            <Empty title="Your account is not linked yet">
              Contact authorized district personnel to arrange verified access.
            </Empty>
            <Link className="button secondary" href="/portal/profile">
              View account guidance
            </Link>
          </Card>
        )}
      </DataState>
      {account.data?.account && (
        <div className="split">
          <Card title="Latest billing record">
            <DataState
              {...bills}
              loaded={!!bills.data}
              empty={bills.data?.items.length === 0}
            >
              {bills.data?.items[0] && <BillCard bill={bills.data.items[0]} />}
            </DataState>
            <Link
              className="text-button"
              style={{ display: "inline-block", marginTop: 12 }}
              href="/portal/bills"
            >
              View all my bills →
            </Link>
          </Card>
          <Card title="Recent concern">
            <DataState
              {...concerns}
              loaded={!!concerns.data}
              empty={concerns.data?.items.length === 0}
            >
              {concerns.data?.items[0] && (
                <>
                  <Badge>{concerns.data.items[0].status}</Badge>
                  <h3 style={{ margin: "14px 0 8px" }}>
                    {concerns.data.items[0].subject}
                  </h3>
                  <p>
                    {concerns.data.items[0].response ||
                      concerns.data.items[0].description}
                  </p>
                </>
              )}
            </DataState>
            <Link
              className="text-button"
              style={{ display: "inline-block", marginTop: 16 }}
              href="/portal/concerns"
            >
              View or submit a concern →
            </Link>
          </Card>
        </div>
      )}
      <Card title="Quick access">
        <div className="quick-grid">
          {[
            {
              href: "bills",
              title: "My bills",
              text: "Charges and verified balances",
              Icon: FileText,
            },
            {
              href: "concerns",
              title: "Service concerns",
              text: "Reports and saved responses",
              Icon: MessageSquare,
            },
            {
              href: "announcements",
              title: "Announcements",
              text: "District news and notices",
              Icon: Bell,
            },
          ].map(({ href, title, text, Icon }) => (
            <Link className="quick-link" key={href} href={`/portal/${href}`}>
              <Icon size={22} />
              <span>
                {title}
                <small>{text}</small>
              </span>
              <ArrowUpRight size={17} />
            </Link>
          ))}
        </div>
      </Card>
      <Card title="District notices">
        <DataState
          {...notices}
          loaded={!!notices.data}
          empty={notices.data?.items.length === 0}
        >
          <div className="stack">
            {recentNotices.map((n) => (
              <NoticeCard key={n.id} notice={n} />
            ))}
          </div>
        </DataState>
        <Link
          className="text-button"
          style={{ display: "inline-block", marginTop: 14 }}
          href="/portal/announcements"
        >
          View all published notices →
        </Link>
      </Card>
    </>
  );
}
export function ConsumerSection({
  section,
  profile,
  billId = "",
  concernId = "",
  ticketId = "",
}: {
  section: string;
  profile: Profile;
  billId?: string;
  concernId?: string;
  ticketId?: string;
}) {
  if (section === "announcements") return <ConsumerNotices />;
  if (section === "help") return <ConsumerHelp />;
  if (section === "profile") return <ConsumerProfile profile={profile} />;
  return (
    <AccountGate>
      {(account) =>
        section === "bills" ? (
          <ConsumerBills />
        ) : section === "payments" ? (
          <ConsumerPayments billId={billId} />
        ) : section === "concerns" ? (
          <ConcernsPage
            profile={profile}
            account={account}
            initialSelected={concernId}
          />
        ) : (
          <RepairsPage profile={profile} initialSelected={ticketId} />
        )
      }
    </AccountGate>
  );
}
