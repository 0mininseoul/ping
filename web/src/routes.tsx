import { useEffect, useState } from "react";
import LandingPage from "./pages/LandingPage";
import InviteView from "./components/invite/InviteView";

export const APP_VERSION = "v0.3.0";
export const DOWNLOAD_URL = "/downloads/Ping-v0.3.0.dmg";

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
        downloadUrl={DOWNLOAD_URL}
        version={APP_VERSION}
      />
    );
  }

  return <LandingPage downloadUrl={DOWNLOAD_URL} version={APP_VERSION} />;
}
