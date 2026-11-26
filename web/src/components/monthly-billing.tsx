"use client";
import { type FormEvent } from "react";
import { useDraft, useResource } from "@/lib/hooks";
import { save } from "@/lib/client";
import {
  money,
  dateLabel,
  positiveMoney,
  dateOnly,
  todayInManila,
} from "@/lib/format";
import type { Account, BillingPlan } from "@/lib/types";
import { Card, Feedback, Field } from "./ui";
import { DataState, useMutation, Refresh } from "./data-ui";

export function MonthlyBilling({
  accounts,
  onSaved,
}: {
  accounts: Account[];
  onSaved?: () => Promise<void>;
}) {
  const plans = useResource<BillingPlan[]>("/api/office/office/billing-plans");
  const status = useResource<{ scheduleActive: boolean }>(
    "/api/office/office/billing-status",
  );
  const [draft, setDraft] = useDraft("office:monthly-billing", {
    accountId: "",
    monthlyAmount: "",
    releaseDate: todayInManila(),
    enabled: true,
  });
  const mutation = useMutation();
  function submit(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      await save("/api/office/office/billing-plans", {
        ...draft,
        monthlyAmount: positiveMoney(draft.monthlyAmount),
        releaseDate: dateOnly(draft.releaseDate || todayInManila()),
      });
      await plans.reload();
      await onSaved?.();
    }, "Monthly billing settings saved. Bills release on the selected date and repeat monthly. A release dated today is available to the consumer now.");
  }
  return (
    <Card title="Automatic monthly billing">
      <p>
        Choose the next release date for each account. Bills repeat on that day
        each month; shorter months use their last day. Select today to release
        the first bill now. Consumers see released bills before their due date.
      </p>
      <Feedback error={status.error} />
      {status.data && (
        <p
          className={
            status.data.scheduleActive ? "feedback success" : "feedback error"
          }
        >
          {status.data.scheduleActive
            ? "Automatic billing schedule is active. Runs daily at 12:05 AM Manila time."
            : "The automatic schedule is not enabled yet. Complete the Supabase billing schedule setup before relying on monthly issuance."}
        </p>
      )}
      <p>
        Bills are due three days after release. Unpaid bills accrue simple
        interest of 1% of the original amount per day after the due date, until
        fully paid.
      </p>
      <Feedback error={mutation.error} success={mutation.success} />
      <form className="form" onSubmit={submit}>
        <fieldset disabled={mutation.busy}>
          <Field label="Monthly billing account">
            <select
              required
              value={draft.accountId}
              onChange={(e) => {
                const plan = plans.data?.find(
                  (p) => p.accountId === e.target.value,
                );
                setDraft({
                  accountId: e.target.value,
                  monthlyAmount: plan?.monthlyAmount ?? "",
                  releaseDate:
                    plan?.nextIssueDate && plan.nextIssueDate >= todayInManila()
                      ? plan.nextIssueDate
                      : todayInManila(),
                  enabled: plan?.enabled ?? true,
                });
              }}
            >
              <option value="">Select an active account</option>
              {accounts
                .filter((a) => a.active)
                .map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.accountNumber} / {a.holderName}
                  </option>
                ))}
            </select>
          </Field>
          <Field label="Monthly amount (PHP)">
            <input
              required
              inputMode="decimal"
              value={draft.monthlyAmount}
              onChange={(e) =>
                setDraft({ ...draft, monthlyAmount: e.target.value })
              }
            />
          </Field>
          <Field label="Next monthly release date">
            <input
              type="date"
              required
              min={todayInManila()}
              max="2100-12-28"
              value={draft.releaseDate || todayInManila()}
              onChange={(e) =>
                setDraft({ ...draft, releaseDate: e.target.value })
              }
            />
          </Field>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={draft.enabled}
              onChange={(e) =>
                setDraft({ ...draft, enabled: e.target.checked })
              }
            />
            <span>Enable automatic monthly bills for this account</span>
          </label>
          <button className="primary" type="submit">
            {mutation.busy ? "Saving…" : "Save recurring plan"}
          </button>
        </fieldset>
      </form>
      <Refresh
        onClick={() => {
          void plans.reload();
          void status.reload();
        }}
        busy={plans.busy || status.busy}
      />
      <DataState
        {...plans}
        loaded={!!plans.data}
        empty={plans.data?.length === 0}
      >
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Account</th>
                <th>Monthly amount</th>
                <th>Next release</th>
                <th>State</th>
              </tr>
            </thead>
            <tbody>
              {plans.data?.map((p) => (
                <tr key={p.accountId}>
                  <td>
                    {accounts.find((a) => a.id === p.accountId)
                      ?.accountNumber ?? p.accountId}
                  </td>
                  <td>{money(p.monthlyAmount)}</td>
                  <td>{p.enabled ? dateLabel(p.nextIssueDate) : "Paused"}</td>
                  <td>{p.enabled ? "Enabled" : "Paused"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </DataState>
      <small>
        Only accounts with an enabled monthly amount receive recurring bills.
        Changing the amount affects future issues.
      </small>
    </Card>
  );
}
