import Decimal from 'decimal.js';
export function money(value: string | number) {
  const amount = new Decimal(value);
  return `₱${amount.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
}
export function balance(due: string | number, payments: (string | number)[]) {
  const paid = Decimal.sum(0, ...payments);
  return { paid: paid.toFixed(2), remaining: Decimal.max(0, new Decimal(due).minus(paid)).toFixed(2) };
}
export function positiveMoney(value: string) {
  if (!/^\d+(\.\d{1,2})?$/.test(value) || new Decimal(value).lte(0) || new Decimal(value).gt('9999999999.99')) throw new Error('Enter a positive amount with at most two decimal places.');
  return new Decimal(value).toFixed(2);
}
export function dateOnly(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Choose a valid date.');
  const date = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value || value < '2000-01-01' || value > '2100-12-31') throw new Error('Choose a valid date between 2000 and 2100.');
  return value;
}
export function dateLabel(value: string) {
  return new Intl.DateTimeFormat('en-PH', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${value.slice(0, 10)}T00:00:00Z`));
}
export function timeLabel(value: string) {
  return new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' }).format(new Date(value));
}
export function todayInManila() { return new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'Asia/Manila' }).format(new Date()); }
