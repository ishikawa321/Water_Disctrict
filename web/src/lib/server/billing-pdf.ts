import "server-only";
import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  PDFDocument,
  PageSizes,
  rgb,
  type PDFPage,
  type PDFFont,
} from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import Decimal from "decimal.js";
import { dateLabel, timeLabel } from "@/lib/format";
import type { BillingExport } from "./billing-export";

const navy = rgb(0.03, 0.11, 0.24),
  blue = rgb(0.02, 0.28, 0.84),
  muted = rgb(0.38, 0.42, 0.51),
  line = rgb(0.87, 0.9, 0.94);
let assets: Promise<Buffer[]> | undefined;
function fonts() {
  return (assets ??= Promise.all(
    ["fonts/DMSans-Regular.ttf", "fonts/DMSans-Bold.ttf", "brand/logo.png"].map(
      (file) => readFile(path.join(process.cwd(), "public", file)),
    ),
  ));
}
export function pdfMoney(value: string) {
  return new Decimal(value).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
function clean(value: string) {
  return value.replace(/[\u0000-\u001f\u007f]/g, " ");
}
function wrap(
  value: string,
  font: PDFFont,
  size: number,
  width: number,
): string[] {
  const result: string[] = [];
  let current = "";
  for (const char of clean(value)) {
    if (current && font.widthOfTextAtSize(current + char, size) > width) {
      result.push(current.trimEnd());
      current = char.trimStart();
    } else current += char;
  }
  if (current || !result.length) result.push(current);
  return result;
}
export async function billingPdf(
  records: BillingExport[],
  options: { single: boolean; generatedAt: Date; preparedBy: string },
): Promise<Uint8Array> {
  if (!records.length)
    throw new Error("At least one billing record is required.");
  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const [regular, bold, logoBytes] = await fonts();
  const [font, strong, logo] = await Promise.all([
    doc.embedFont(regular, { subset: true }),
    doc.embedFont(bold, { subset: true }),
    doc.embedPng(logoBytes),
  ]);
  doc.setTitle(
    options.single
      ? `Billing record ${records[0].billNumber}`
      : "Billing records",
  );
  doc.setAuthor("Maramag Water District");
  doc.setCreator("Water District Connect");
  doc.setCreationDate(options.generatedAt);
  doc.setLanguage("en-PH");
  const stamp = timeLabel(options.generatedAt.toISOString());
  const draw = (
    page: PDFPage,
    text: string,
    x: number,
    y: number,
    size = 10,
    bold = false,
    color = navy,
  ) =>
    page.drawText(clean(text), {
      x,
      y,
      size,
      font: bold ? strong : font,
      color,
    });
  const header = (page: PDFPage, title: string) => {
    const { width, height } = page.getSize();
    page.drawImage(logo, {
      x: width - 80,
      y: height - 77,
      width: 42,
      height: 42,
    });
    draw(page, "MARAMAG WATER DISTRICT", 36, height - 43, 12, true, blue);
    draw(page, "Water District Connect", 36, height - 61, 9, false, muted);
    draw(page, title, 36, height - 100, 23, true);
    draw(
      page,
      `Generated ${stamp} (Asia/Manila)`,
      36,
      height - 119,
      9,
      false,
      muted,
    );
  };
  if (options.single) {
    let page = doc.addPage(PageSizes.A4);
    header(page, "Billing record");
    let y = page.getHeight() - 155;
    const lines = (label: string, value: string) => {
      const parts = wrap(value, font, 11, page.getWidth() - 84);
      const height = 18 + parts.length * 16 + 12;
      if (y - height < 85) {
        page = doc.addPage(PageSizes.A4);
        header(page, "Billing record · continued");
        y = page.getHeight() - 155;
      }
      draw(page, label, 42, y, 9, true, muted);
      y -= 18;
      for (const part of parts) {
        draw(page, part, 42, y, 11);
        y -= 16;
      }
      y -= 12;
    };
    const b = records[0];
    lines("BILL NUMBER", b.billNumber);
    lines("SERVICE ACCOUNT", b.accountNumber);
    lines("ACCOUNT HOLDER", b.holderName);
    lines("SERVICE ADDRESS", b.serviceAddress);
    lines("DUE DATE", dateLabel(b.dueDate));
    if (y < 285) {
      page = doc.addPage(PageSizes.A4);
      header(page, "Billing record · amounts");
      y = page.getHeight() - 155;
    }
    page.drawLine({
      start: { x: 42, y: y + 5 },
      end: { x: page.getWidth() - 42, y: y + 5 },
      color: line,
    });
    y -= 21;
    for (const [label, value] of [
      ["Original charge", b.baseAmount],
      [`Accrued interest (${b.interestDays} days)`, b.interestAmount],
      ["Total charges", b.total],
      ["Verified payments", b.paid],
      ["Remaining balance", b.remaining],
    ]) {
      const emph = label === "Remaining balance";
      if (emph)
        page.drawRectangle({
          x: 36,
          y: y - 10,
          width: page.getWidth() - 72,
          height: 32,
          color: rgb(0.9, 0.97, 0.99),
        });
      draw(page, label, 44, y, 11, emph);
      const text = `PHP ${pdfMoney(value)}`;
      draw(
        page,
        text,
        page.getWidth() -
          44 -
          (emph ? strong : font).widthOfTextAtSize(text, 11),
        y,
        11,
        emph,
      );
      y -= 34;
    }
    lines("PREPARED BY", options.preparedBy);
  } else {
    let page!: PDFPage;
    let y = 0;
    const widths = [171, 70, 100, 90, 100, 100, 139];
    const xs = [36];
    for (let i = 0; i < widths.length; i++) xs.push(xs[i] + widths[i]);
    const headings = [
      "Bill / account",
      "Due date",
      "Original",
      "Interest",
      "Total",
      "Paid",
      "Remaining",
    ];
    const newPage = () => {
      page = doc.addPage([PageSizes.A4[1], PageSizes.A4[0]]);
      header(page, "Billing records");
      y = page.getHeight() - 146;
      page.drawRectangle({
        x: 36,
        y: y - 7,
        width: 770,
        height: 25,
        color: rgb(0.94, 0.96, 0.98),
      });
      headings.forEach((h, i) => draw(page, h, xs[i] + 5, y, 9, true));
      y -= 33;
    };
    newPage();
    for (const b of records) {
      const names = [
        ...wrap(b.billNumber, strong, 9, widths[0] - 12),
        ...wrap(b.accountNumber, font, 8, widths[0] - 12),
        ...wrap(b.holderName, font, 8, widths[0] - 12),
      ];
      const rowHeight = Math.max(36, names.length * 13 + 12);
      if (y - rowHeight < 75) newPage();
      names.forEach((t, i) =>
        draw(page, t, xs[0] + 5, y - i * 13, i === 0 ? 9 : 8, i === 0),
      );
      draw(page, b.dueDate, xs[1] + 5, y, 8);
      [b.baseAmount, b.interestAmount, b.total, b.paid, b.remaining].forEach(
        (v, i) => {
          const t = pdfMoney(v);
          const size = 8;
          draw(
            page,
            t,
            xs[i + 3] - 7 - font.widthOfTextAtSize(t, size),
            y,
            size,
          );
        },
      );
      y -= rowHeight;
      page.drawLine({
        start: { x: 36, y: y + 7 },
        end: { x: 806, y: y + 7 },
        color: line,
        thickness: 0.4,
      });
    }
    if (y < 130) newPage();
    y -= 14;
    draw(
      page!,
      `${records.length} selected billing records · All amounts in PHP`,
      40,
      y,
      10,
      true,
    );
    y -= 23;
    const sum = (
      field: "baseAmount" | "interestAmount" | "total" | "paid" | "remaining",
    ) => Decimal.sum(0, ...records.map((r) => r[field])).toFixed(2);
    draw(page!, "TOTALS", 41, y, 9, true);
    (
      ["baseAmount", "interestAmount", "total", "paid", "remaining"] as const
    ).forEach((field, i) => {
      const t = pdfMoney(sum(field));
      draw(
        page!,
        t,
        xs[i + 3] - 7 - strong.widthOfTextAtSize(t, 8),
        y,
        8,
        true,
      );
    });
    y -= 25;
    wrap(`Prepared by: ${options.preparedBy}`, font, 9, 760).forEach(
      (text, i) => draw(page!, text, 41, y - i * 12, 9),
    );
  }
  const pages = doc.getPages();
  pages.forEach((page, i) => {
    page.drawLine({
      start: { x: 36, y: 48 },
      end: { x: page.getWidth() - 36, y: 48 },
      color: line,
      thickness: 0.5,
    });
    draw(
      page,
      "Saved billing balances at generation time. Payment history contains verified receipts.",
      36,
      34,
      7,
      false,
      muted,
    );
    const count = `Page ${i + 1} of ${pages.length}`;
    draw(
      page,
      count,
      page.getWidth() - 36 - font.widthOfTextAtSize(count, 7),
      21,
      7,
      false,
      muted,
    );
  });
  return doc.save();
}
