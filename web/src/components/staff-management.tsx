"use client";
import { useState, type FormEvent } from "react";
import { save } from "@/lib/client";
import { useResource } from "@/lib/hooks";
import type { StaffMember } from "@/lib/types";
import { Card, Field, Feedback, Badge } from "./ui";
import { DataState, PageHeader, Refresh, useMutation } from "./data-ui";
type Invitation = {
  id: string;
  email: string;
  display_name: string;
  status: string;
  expires_at: string;
};
export function StaffDirectory() {
  const records = useResource<StaffMember[]>("/api/office/admin/staff");
  const invites = useResource<Invitation[]>(
    "/api/office/admin/staff-invitations",
  );
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [link, setLink] = useState("");
  const action = useMutation();
  function reload() {
    void records.reload();
    void invites.reload();
  }
  function submit(e: FormEvent) {
    e.preventDefault();
    void action.run(async () => {
      const result = await save<{ token: string }>(
        "/api/office/admin/staff-invitations",
        { email, displayName: name },
      );
      setLink(
        `${window.location.origin}/staff/accept#${encodeURIComponent(result.token)}`,
      );
      setName("");
      setEmail("");
      reload();
    }, "Invitation created. Copy the private link and send it to the invited Staff member.");
  }
  return (
    <>
      <PageHeader
        title="Staff management"
        subtitle="Invite personnel, manage access and review invitation status."
      >
        <Refresh onClick={reload} busy={records.busy || invites.busy} />
      </PageHeader>
      <Feedback error={action.error} success={action.success} />
      <Card title="Invite Staff">
        <form className="form" onSubmit={submit}>
          <fieldset disabled={action.busy}>
            <Field label="Staff full name">
              <input
                required
                maxLength={200}
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </Field>
            <Field label="Staff email">
              <input
                type="email"
                required
                maxLength={254}
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </Field>
            <button className="primary">Create Staff invitation</button>
          </fieldset>
        </form>
        <p>
          The invitation is bound to this email and expires after seven days.
          The recipient sets their own password and confirms their email.
          Existing Consumer/Admin accounts cannot be changed into Staff here.
        </p>
        {link && (
          <div className="form">
            <Field label="Private Staff invitation link">
              <input readOnly value={link} onFocus={(e) => e.target.select()} />
            </Field>
            <button
              className="secondary"
              onClick={() =>
                void action.run(
                  () => navigator.clipboard.writeText(link),
                  "Invitation link copied.",
                )
              }
            >
              Copy invitation link
            </button>
            <small>
              This link is shown only in this browser. It is not sent
              automatically.
            </small>
          </div>
        )}
      </Card>
      <Card title="Office personnel">
        <DataState {...records} loaded={!!records.data}>
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Access</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {records.data?.map((p) => (
                  <tr key={p.userId}>
                    <td>{p.displayName}</td>
                    <td>{p.email ?? ""}</td>
                    <td>{p.role}</td>
                    <td>
                      <Badge>{p.active ? "Active" : "Disabled"}</Badge>
                    </td>
                    <td>
                      {p.role === "staff" && (
                        <button
                          className="secondary"
                          disabled={action.busy}
                          onClick={() =>
                            void action.run(async () => {
                              await save(
                                `/api/office/admin/staff/${p.userId}/access`,
                                { active: !p.active },
                              );
                              reload();
                            }, "Staff access updated.")
                          }
                        >
                          {p.active ? "Disable Staff" : "Enable Staff"}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </DataState>
      </Card>
      <Card title="Staff invitations">
        <DataState
          {...invites}
          loaded={!!invites.data}
          empty={invites.data?.length === 0}
        >
          <div className="record-list">
            {invites.data?.map((i) => (
              <div key={i.id}>
                <strong>{i.display_name}</strong>
                <p>
                  {i.email} · {i.status} · Expires{" "}
                  {new Date(i.expires_at).toLocaleDateString()}
                </p>
                {i.status === "Pending" && (
                  <button
                    className="secondary"
                    disabled={action.busy}
                    onClick={() =>
                      void action.run(async () => {
                        await save(
                          `/api/office/admin/staff-invitations/${i.id}/revoke`,
                          {},
                        );
                        reload();
                      }, "Invitation revoked.")
                    }
                  >
                    Revoke invitation
                  </button>
                )}
              </div>
            ))}
          </div>
        </DataState>
      </Card>
    </>
  );
}
