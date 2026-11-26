import { AuthForm } from "@/components/auth-form";
export default async function Login({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string }>;
}) {
  const { reason } = await searchParams;
  return <AuthForm reason={reason} />;
}
