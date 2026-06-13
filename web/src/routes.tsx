import { useEffect, useState } from "react";
import LandingPage from "./pages/LandingPage";
import InviteView from "./components/invite/InviteView";

export const MAC_APP_VERSION = "v0.3.46";
export const WINDOWS_APP_VERSION = "v0.3.46";
export const MAC_DOWNLOAD_URL = "/downloads/Ping-v0.3.46.dmg";
export const WINDOWS_DOWNLOAD_URL = "/downloads/windows/PingSetup-v0.3.46.exe";

function matchInvite(pathname: string): string | null {
  const m = pathname.match(/^\/invite\/([^/]+)\/?$/);
  return m?.[1] ? decodeURIComponent(m[1]) : null;
}

export default function Routes() {
  const [pathname, setPathname] = useState(
    typeof window === "undefined" ? "/" : window.location.pathname,
  );

  useEffect(() => {
    const onPop = () => setPathname(window.location.pathname);
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  const token = matchInvite(pathname);
  if (token) {
    return (
      <InviteView
        token={token}
        macDownloadUrl={MAC_DOWNLOAD_URL}
        windowsDownloadUrl={WINDOWS_DOWNLOAD_URL}
        macVersion={MAC_APP_VERSION}
        windowsVersion={WINDOWS_APP_VERSION}
      />
    );
  }

  return (
    <LandingPage
      macDownloadUrl={MAC_DOWNLOAD_URL}
      windowsDownloadUrl={WINDOWS_DOWNLOAD_URL}
      macVersion={MAC_APP_VERSION}
      windowsVersion={WINDOWS_APP_VERSION}
    />
  );
}
