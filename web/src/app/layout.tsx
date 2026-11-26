import type { Metadata } from 'next';
import localFont from 'next/font/local';
import './globals.css';
const dmSans = localFont({ src: [
  { path: '../../public/fonts/DMSans-Regular.ttf', weight: '400' },
  { path: '../../public/fonts/DMSans-Medium.ttf', weight: '500' },
  { path: '../../public/fonts/DMSans-SemiBold.ttf', weight: '600' },
  { path: '../../public/fonts/DMSans-Bold.ttf', weight: '700' },
], variable: '--font-dm-sans', display: 'swap' });
export const metadata: Metadata = { title: { default: 'Water District Connect', template: '%s · Water District Connect' }, description: 'Maramag Water District consumer and office services.', robots: { index: false, follow: false }, icons: { icon: '/brand/logo.png' } };
export default function RootLayout({ children }: { children: React.ReactNode }) { return <html lang="en"><body className={dmSans.variable}>{children}</body></html>; }
