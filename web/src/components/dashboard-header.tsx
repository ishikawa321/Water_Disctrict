import Image from "next/image";
export function DashboardHeader({
  title,
  subtitle,
}: {
  title: string;
  subtitle: string;
}) {
  return (
    <div className="dashboard-header">
      <Image
        src="/brand/logo.png"
        alt="Maramag Water District"
        width={56}
        height={56}
      />
      <div>
        <span className="eyebrow">Maramag Water District</span>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
    </div>
  );
}
