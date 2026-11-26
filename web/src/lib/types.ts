export type Role = "admin" | "staff" | "client";
export type Profile = {
  userId: string;
  displayName: string;
  role: Role;
  email: string;
};
export type ClientRegistration = {
  userId: string;
  fullName: string;
  serviceAddress: string;
  email: string;
  status: string;
  submittedAt: string;
  emailConfirmedAt: string | null;
};
export type Account = {
  id: string;
  accountNumber: string;
  holderName: string;
  serviceAddress: string;
  active: boolean;
};
export type Bill = {
  id: string;
  billNumber: string;
  accountNumber: string;
  periodStart: string;
  periodEnd: string;
  releaseDate?: string;
  dueDate: string;
  amountDue: string | number;
  baseAmount?: string | number;
  interestAmount?: string | number;
  interestDays?: number;
  paid: string | number;
  remaining: string | number;
};
export type Payment = {
  billId?: string;
  receiptReference: string;
  billNumber: string;
  accountNumber: string;
  paymentDate: string;
  amountPaid: string | number;
  verifiedAt: string | null;
};
export type BillingPlan = {
  accountId: string;
  monthlyAmount: string;
  enabled: boolean;
  nextIssueDate: string;
};
export type Notice = {
  id: string;
  title: string;
  message: string;
  published: boolean;
  updatedAt: string;
};
export type Concern = {
  id: string;
  accountId: string;
  accountNumber: string;
  holderName: string;
  category: string;
  subject: string;
  description: string;
  status: string;
  response: string | null;
  createdAt: string;
  reviewedAt: string | null;
  ticketId: string | null;
  repairDispatchedAt?: string | null;
  version: number;
  latitude?: number | null;
  longitude?: number | null;
  locationNote?: string | null;
};
export type Ticket = {
  id: string;
  concernId: string;
  accountNumber: string;
  subject: string;
  status: string;
  assignedTo: string | null;
  assignedToUserId: string | null;
  latestUpdate: string;
  updatedAt: string;
  version: number;
};
export type History = {
  id: number;
  status: string;
  note: string;
  changedBy: string;
  assignedTo: string | null;
  changedAt: string;
};
export type TicketDetails = { ticket: Ticket; history: History[] };
export type StaffMember = {
  userId: string;
  displayName: string;
  role: string;
  active?: boolean;
  email?: string;
};
export type PageResult<T> = { items: T[]; hasMore: boolean; page: number };
export type LinkedAccount = { account: Account | null };
export type ConsumerSummary = {
  outstanding: string;
  billCount: number;
  nextDueDate: string | null;
};
