import { useEffect, useState } from "react";

export type DetectedOS = "windows" | "mac" | "other";

/**
 * 방문자 OS를 추정한다. userAgentData(최신) → platform → userAgent 순으로 확인.
 * 서버/추정 불가 시 "other"를 반환한다.
 */
export function detectOS(): DetectedOS {
  if (typeof navigator === "undefined") return "other";

  const uaData = (
    navigator as Navigator & { userAgentData?: { platform?: string } }
  ).userAgentData;
  const platform = (uaData?.platform || navigator.platform || "").toLowerCase();
  const ua = navigator.userAgent.toLowerCase();

  if (platform.includes("win") || ua.includes("windows")) return "windows";
  if (
    platform.includes("mac") ||
    ua.includes("macintosh") ||
    ua.includes("mac os")
  ) {
    return "mac";
  }
  return "other";
}

/**
 * 클라이언트에서 OS를 감지한다. 초기값은 "other"로 두어 하이드레이션 불일치를
 * 피하고, 마운트 후 실제 값으로 갱신한다.
 */
export function useOS(): DetectedOS {
  const [os, setOS] = useState<DetectedOS>("other");
  useEffect(() => {
    setOS(detectOS());
  }, []);
  return os;
}
