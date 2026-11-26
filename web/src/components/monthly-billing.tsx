"use client";
import { type FormEvent } from "react";
import { useDraft, useResource } from "@/lib/hooks";
import { save } from "@/lib/client";
import { money, dateLabel, positiveMoney } from "@/lib/format";
import type { Account, BillingPlan } from "@/lib/types";
import { Card, Feedback, Field } from "./ui";
import { DataState, useMutation, Refresh } from "./data-ui";

export function MonthlyBilling({ accounts }: { accounts: Account[] }) {
  const plans = useResource<BillingPlan[]>("/api/office/office/billing-plans");
  const status = useResource<{ scheduleActive: boolean }>(
    "/api/office/office/billing-status",
  );
  const [draft, setDraft] = useDraft("office:monthly-billing", {
    accountId: "",
    monthlyAmount: "",
    enabled: true,
  });
  const mutation = useMutation();
  function submit(event: FormEvent) {
    event.preventDefault();
    void mutation.run(async () => {
      await save("/api/office/office/billing-plans", {
        ...draft,
        monthlyAmount: positiveMoney(draft.monthlyAmount),
      });
      await plans.reload();
    }, "Monthly billing settings saved. Bills will be issued on the scheduled 28th; saving a plan does not create a bill now.");
  }
  return (
    <Card title="Automatic monthly billing">
      <p>
        These are monthly plans for future bills. Consumers see each bill as
        soon as it is issued, even before its due date. Saving a plan does not
        create a bill immediately.
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
        Bills issue on the 28th and are due three days later. Unpaid bills
        accrue simple interest of 1% of the original amount per day after the
        due date, until fully paid.
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
            {mutation.busy ? "Saving…" : "Save monthly billing"}
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
                <th>Next bill issue</th>
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
