"use client";
import { useState, type ReactNode } from "react";
import Link from "next/link";
import {
  CircleHelp,
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
  ConsumerSummary,
} from "@/lib/types";
import { Badge, Card, Empty } from "./ui";
import { DataState, PageHeader, Pager, Refresh } from "./data-ui";
import { Modal } from "./modal";
import { DashboardHeader } from "./dashboard-header";
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
  const [instructions, setInstructions] = useState(false);
  const paid = Number(bill.remaining) <= 0;
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  return (
    <article className="notice bill-card">
      <div className="row spread wrap">
        <h3>Bill {bill.billNumber}</h3>
        <Badge>
          {paid ? "Paid" : bill.dueDate < today ? "Overdue" : "Unpaid"}
        </Badge>
      </div>
      <strong className="bill-amount">{money(bill.remaining)}</strong>
      <p>Remaining balance · Due {dateLabel(bill.dueDate)}</p>
      <details className="record-details">
        <summary>Billing details</summary>
        <dl className="detail-grid">
          <div>
            <dt>Service account</dt>
            <dd>{bill.accountNumber}</dd>
          </div>
          <div>
            <dt>Billing period</dt>
            <dd>
              {dateLabel(bill.periodStart)} – {dateLabel(bill.periodEnd)}
            </dd>
          </div>
          <div>
            <dt>Original amount</dt>
            <dd>{money(bill.amountDue)}</dd>
          </div>
          <div>
            <dt>Verified payments</dt>
            <dd>{money(bill.paid)}</dd>
          </div>
        </dl>
      </details>
      <div className="row wrap">
        {!paid && (
          <button className="primary" onClick={() => setInstructions(true)}>
            Payment instructions
          </button>
        )}
        <Link
          className="button secondary"
          href={`/portal/payments?billId=${bill.id}`}
        >
          View payment history <ArrowUpRight size={16} />
        </Link>
      </div>
      {instructions && (
        <Modal
          title="Payment instructions"
          onClose={() => setInstructions(false)}
        >
          <div className="stack">
            <h3>Maramag Water District</h3>
            <p>
              Contact the district for accepted payment channels and
              requirements.
            </p>
            <dl className="detail-grid">
              <div>
                <dt>Service account</dt>
                <dd>{bill.accountNumber}</dd>
              </div>
              <div>
                <dt>Bill reference</dt>
                <dd>{bill.billNumber}</dd>
              </div>
              <div>
                <dt>Remaining balance</dt>
                <dd>{money(bill.remaining)}</dd>
              </div>
              <div>
                <dt>Due date</dt>
                <dd>{dateLabel(bill.dueDate)}</dd>
              </div>
            </dl>
            <p>
              Keep your official receipt. Payments appear in your account after
              district verification.
            </p>
            <button
              className="secondary"
              onClick={() => setInstructions(false)}
            >
              Close instructions
            </button>
          </div>
        </Modal>
      )}
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
              <div className="stack">
                {records.data?.items.map((payment, index) => (
                  <article
                    className="notice"
                    key={`${payment.receiptReference}-${index}`}
                  >
                    <div className="row spread wrap">
                      <h3>{payment.receiptReference}</h3>
                      <Badge>Verified</Badge>
                    </div>
                    <strong className="bill-amount">
                      {money(payment.amountPaid)}
                    </strong>
                    <p>Paid {dateLabel(payment.paymentDate)}</p>
                    <details className="record-details">
                      <summary>Payment details</summary>
                      <dl className="detail-grid">
                        <div>
                          <dt>Bill reference</dt>
                          <dd>{payment.billNumber}</dd>
                        </div>
                        <div>
                          <dt>Service account</dt>
                          <dd>{payment.accountNumber}</dd>
                        </div>
                        <div>
                          <dt>Verified</dt>
                          <dd>
                            {payment.verifiedAt
                              ? timeLabel(payment.verifiedAt)
                              : "Verification date unavailable"}
                          </dd>
                        </div>
                      </dl>
                    </details>
                  </article>
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
      <details className="record-details">
        <summary>Read notice</summary>
        <p className="prose">{notice.message}</p>
      </details>
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
      <Card title="Account details">
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
        <hr />
        <h3>Linked service account</h3>
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
      <Card>
        <div className="row wrap">
          <CircleHelp size={20} />
          <p>Need help with your account or a payment?</p>
          <Link className="button secondary" href="/portal/help">
            Help & guidance
          </Link>
        </div>
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
  const [showAdvisory, setShowAdvisory] = useState(false);
  const account = useResource<LinkedAccount>("/api/consumer/account");
  const bills = useResource<PageResult<Bill>>(
    account.data?.account ? "/api/consumer/bills?page=0" : null,
  );
  const summary = useResource<ConsumerSummary>(
    account.data?.account ? "/api/consumer/summary" : null,
  );
  const concerns = useResource<PageResult<Concern>>(
    account.data?.account ? "/api/consumer/concerns?page=0" : null,
  );
  const activity = useResource<PageResult<Payment>>(
    account.data?.account ? "/api/consumer/activity" : null,
  );
  const notices = useResource<PageResult<Notice>>(
    "/api/consumer/announcements?page=0",
  );
  const refresh = () => {
    void account.reload();
    void summary.reload();
    void bills.reload();
    void concerns.reload();
    void notices.reload();
    void activity.reload();
  };
  const latestNotice = [...(notices.data?.items ?? [])].sort(
    (a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt),
  )[0];
  const recent = concerns.data?.items[0];
  const advisory = notices.data?.items
    .slice(0, 10)
    .find((notice) => notice.title.startsWith(interruptionPrefix));
  return (
    <>
      <DashboardHeader
        title={`Hello, ${profile.displayName.split(" ")[0]}.`}
        subtitle="Your water services and district updates."
      />
      <div className="page-header">
        <p>
          {account.data?.account
            ? `Service account ${account.data.account.accountNumber}`
            : "Your connected district account"}
        </p>
        <Refresh
          onClick={refresh}
          busy={
            account.busy ||
            bills.busy ||
            summary.busy ||
            concerns.busy ||
            notices.busy ||
            activity.busy
          }
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
      <div className="dashboard-columns">
        <div className="stack">
          {account.data?.account && (
            <Card
              title="Outstanding balance"
              className="consumer-balance water-surface"
            >
              <DataState {...summary} loaded={!!summary.data}>
                {summary.data && (
                  <>
                    <strong className="balance-amount">
                      {money(summary.data.outstanding)}
                    </strong>
                    <p className="due-pill">
                      {summary.data.nextDueDate
                        ? `Next unpaid due date: ${dateLabel(summary.data.nextDueDate)}`
                        : "No unpaid bills"}
                    </p>
                    <small>
                      {summary.data.billCount} saved billing records for your
                      linked account
                    </small>
                  </>
                )}
              </DataState>
              <Link className="balance-action" href="/portal/bills">
                <FileText size={20} />
                View bill <ArrowUpRight size={18} />
              </Link>
            </Card>
          )}
          <Card
            className={`service-advisory ${advisory ? "has-advisory" : ""}`}
            title={advisory ? "Service advisory" : "Service updates"}
          >
            <DataState {...notices} loaded={!!notices.data}>
              {notices.data && (
                <>
                  <p>
                    {advisory
                      ? "View affected areas and schedule in the published advisory."
                      : "No interruption notice in the latest district updates. Live service status is not available."}
                  </p>
                  {advisory ? (
                    <>
                      <button
                        type="button"
                        className="text-button"
                        onClick={() => setShowAdvisory(true)}
                      >
                        Read service advisory →
                      </button>
                      {showAdvisory && (
                        <Modal
                          title="Service advisory"
                          onClose={() => setShowAdvisory(false)}
                        >
                          <NoticeCard notice={advisory} />
                          <button
                            className="secondary"
                            onClick={() => setShowAdvisory(false)}
                          >
                            Close advisory
                          </button>
                        </Modal>
                      )}
                    </>
                  ) : (
                    <Link className="text-button" href="/portal/announcements">
                      View published notices
                    </Link>
                  )}
                </>
              )}
            </DataState>
          </Card>
          <Card title="Quick access" className="consumer-quick">
            <div className="quick-grid">
              {[
                {
                  href: "bills",
                  title: "My bills",
                  text: "Charges and balances",
                  Icon: FileText,
                },
                {
                  href: "concerns?new=1",
                  title: "Report issue",
                  text: "Submit a service concern",
                  Icon: MessageSquare,
                },
                {
                  href: "repairs",
                  title: "Repairs",
                  text: "Follow saved progress",
                  Icon: Wrench,
                },
              ].map(({ href, title, text, Icon }) => (
                <Link
                  className="quick-link"
                  key={href}
                  href={`/portal/${href}`}
                >
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
          {account.data?.account && (
            <Card title="Latest billing record">
              <DataState
                {...bills}
                loaded={!!bills.data}
                empty={bills.data?.items.length === 0}
              >
                {bills.data?.items[0] && (
                  <BillCard bill={bills.data.items[0]} />
                )}
              </DataState>
              <Link className="text-button" href="/portal/bills">
                View all my bills →
              </Link>
            </Card>
          )}
        </div>
        <div className="stack">
          {account.data?.account && (
            <Card title="Recent activity">
              <DataState {...activity} loaded={!!activity.data}>
                {activity.data &&
                  (activity.data.items[0] ? (
                    <article className="activity-record">
                      <Badge>Verified</Badge>
                      <h3>Payment verified</h3>
                      <p>
                        {dateLabel(activity.data.items[0].paymentDate)} ·{" "}
                        {money(activity.data.items[0].amountPaid)}
                      </p>
                      <small>
                        Receipt {activity.data.items[0].receiptReference}
                      </small>
                      <Link
                        className="button secondary"
                        href={`/portal/payments?billId=${activity.data.items[0].billId}`}
                      >
                        View transaction
                      </Link>
                    </article>
                  ) : (
                    <Empty title="No recent transactions">
                      Updates will appear here.
                    </Empty>
                  ))}
              </DataState>
            </Card>
          )}
          {account.data?.account && (
            <Card title="Recent concern">
              <DataState
                {...concerns}
                loaded={!!concerns.data}
                empty={concerns.data?.items.length === 0}
              >
                {recent && (
                  <>
                    <Badge>{recent.status}</Badge>
                    <h3>{recent.subject}</h3>
                    <p className="prose">
                      {recent.response || recent.description}
                    </p>
                    <small>Received {timeLabel(recent.createdAt)}</small>
                    <Link
                      className="button secondary"
                      href={`/portal/concerns?concernId=${recent.id}`}
                    >
                      View concern
                    </Link>
                  </>
                )}
              </DataState>
            </Card>
          )}
          <Card title="Latest district notice">
            <DataState {...notices} loaded={!!notices.data}>
              {latestNotice ? (
                <NoticeCard notice={latestNotice} />
              ) : (
                notices.data && (
                  <Empty title="No published advisory">
                    Published district updates will appear here.
                  </Empty>
                )
              )}
            </DataState>
            <Link className="text-button" href="/portal/announcements">
              View all published notices →
            </Link>
          </Card>
        </div>
      </div>
    </>
  );
}
export function ConsumerSection({
  section,
  profile,
  billId = "",
  concernId = "",
  ticketId = "",
  new: newConcern = "",
}: {
  section: string;
  profile: Profile;
  billId?: string;
  concernId?: string;
  ticketId?: string;
  new?: string;
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
            initialShow={newConcern === "1"}
          />
        ) : (
          <RepairsPage profile={profile} initialSelected={ticketId} />
        )
      }
    </AccountGate>
  );
}
