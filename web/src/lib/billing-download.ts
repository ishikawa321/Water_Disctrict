"use client";
export async function downloadBillingPdf(billIds: string[], single = false) {
  const response = await fetch(
    single
      ? `/api/office/billing-pdf?billId=${encodeURIComponent(billIds[0])}`
      : "/api/office/billing-pdf",
    single
      ? { cache: "no-store" }
      : {
          method: "POST",
          cache: "no-store",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ billIds }),
        },
  );
  if (!response.ok) {
    const error = await response.json().catch(() => null);
    if (["session_lost", "access_lost"].includes(error?.code))
      window.dispatchEvent(new Event("waterdistrict:access-lost"));
    throw new Error(
      error?.detail ??
        "The billing PDF could not be prepared. Refresh to retry.",
    );
  }
  if (!response.headers.get("content-type")?.startsWith("application/pdf"))
    throw new Error("The server did not return a billing PDF. Please retry.");
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download =
    response.headers
      .get("content-disposition")
      ?.match(/filename="([^"]+)"/)?.[1] ?? "billing-records.pdf";
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
