import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { ArrowLeft, ArrowUpRight, Download, Smartphone } from "lucide-react";
import release from "@/lib/android-release.json";

export const metadata: Metadata = {
  title: "Download for Android",
  description: "Download the signed Water District Connect Android app.",
};

export default function AndroidDownload() {
  return (
    <main className="download-page">
      <Link className="text-button row" href="/">
        <ArrowLeft size={18} />
        Back to the website
      </Link>
      <section className="download-hero water-surface">
        <Image
          src="/brand/logo.png"
          alt="Maramag Water District logo"
          width={76}
          height={76}
        />
        <span className="eyebrow">
          Water District Connect · Student project
        </span>
        <h1>
          Your water services.
          <br />
          On your Android phone.
        </h1>
        <p>
          Download the Android app and sign in with your existing Water District
          account.
        </p>
        <a className="button primary" href={release.apkUrl}>
          <Download size={20} />
          Download APK
        </a>
        <small>
          Version {release.version} ·{" "}
          {(release.sizeBytes / 1_000_000).toFixed(1)} MB · Android{" "}
          {release.minimumAndroid} or later
        </small>
      </section>
      <div className="download-columns">
        <section className="card">
          <div className="row">
            <Smartphone size={24} />
            <h2>Install in a few steps</h2>
          </div>
          <ol className="install-steps">
            <li>
              Tap <strong>Download APK</strong> and wait for the download to
              finish.
            </li>
            <li>
              Open the downloaded file and tap <strong>Install</strong>.
            </li>
            <li>
              If Android asks, allow your browser or Files app to install apps,
              then return to the installer.
            </li>
            <li>
              Open <strong>Water District Connect</strong> and sign in. An
              internet connection is required.
            </li>
          </ol>
          <p>
            This APK works on Android. For iPhone or a computer, use the web
            app.
          </p>
          <Link className="button secondary" href="/app">
            Open web app <ArrowUpRight size={17} />
          </Link>
        </section>
        <section className="card">
          <h2>One account. Shared records.</h2>
          <p>
            The mobile app uses the existing Supabase identity and district
            records. It includes Consumer, Admin and invited Staff access. Staff
            can confirm payments and complete assigned repairs for Admin review.
          </p>
          <p>
            This version includes the updated app design, announcement
            indicators and billing-history PDF sharing for Consumers and Admins.
          </p>
          <p>
            Installing the app does not create an account or change your role.
            Contact authorized district personnel for account linking.
          </p>
          <details className="record-details">
            <summary>Release details and checksum</summary>
            <dl className="detail-grid">
              <div>
                <dt>Version</dt>
                <dd>
                  {release.version} ({release.buildNumber})
                </dd>
              </div>
              <div>
                <dt>Package</dt>
                <dd>{release.applicationId}</dd>
              </div>
              <div>
                <dt>File</dt>
                <dd>{release.fileName}</dd>
              </div>
              <div>
                <dt>Architecture</dt>
                <dd>Universal APK: ARM, ARM64 and x86-64</dd>
              </div>
            </dl>
            <p>SHA-256</p>
            <code className="apk-checksum">{release.sha256}</code>
            <a className="text-button" href={release.checksumUrl}>
              Download checksum
            </a>
            <p>
              The APK is signed with the project’s release certificate. Keep the
              same app installed to receive compatible future releases.
            </p>
          </details>
        </section>
      </div>
    </main>
  );
}
