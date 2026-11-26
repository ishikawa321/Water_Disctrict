import { dateLabel, money, timeLabel } from '@/lib/format';
import type { Payment } from '@/lib/types';
import { Badge } from './ui';
export function PaymentTable({ payments }: { payments: Payment[] }) {
  return <div className="table-scroll"><table><thead><tr><th>Receipt / reference</th><th>Bill / account</th><th>Payment date</th><th>Amount</th><th>Verification</th></tr></thead><tbody>{payments.map((payment, index) => <tr key={`${payment.receiptReference}:${index}`}><td>{payment.receiptReference}</td><td>{payment.billNumber}<small>{payment.accountNumber}</small></td><td>{dateLabel(payment.paymentDate)}</td><td className="amount">{money(payment.amountPaid)}</td><td><Badge>Verified</Badge>{payment.verifiedAt && <small>{timeLabel(payment.verifiedAt)}</small>}</td></tr>)}</tbody></table></div>;
}
