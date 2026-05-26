import SiteNav from "@/components/sections/SiteNav";
import Hero from "@/components/sections/Hero";
import DemoStrip from "@/components/sections/DemoStrip";
import FeaturesGrid from "@/components/sections/FeaturesGrid";
import SpecStrip from "@/components/sections/SpecStrip";
import FinalCTA from "@/components/sections/FinalCTA";
import SiteFooter from "@/components/sections/SiteFooter";

interface LandingPageProps {
  macDownloadUrl: string;
  windowsDownloadUrl: string;
  macVersion: string;
  windowsVersion: string;
}

export default function LandingPage({
  macDownloadUrl,
  windowsDownloadUrl,
  macVersion,
  windowsVersion,
}: LandingPageProps) {
  return (
    <main className="relative min-h-screen">
      <SiteNav
        macDownloadUrl={macDownloadUrl}
        windowsDownloadUrl={windowsDownloadUrl}
      />
      <Hero
        macDownloadUrl={macDownloadUrl}
        windowsDownloadUrl={windowsDownloadUrl}
        macVersion={macVersion}
        windowsVersion={windowsVersion}
      />
      <DemoStrip />
      <FeaturesGrid />
      <SpecStrip />
      <FinalCTA
        macDownloadUrl={macDownloadUrl}
        windowsDownloadUrl={windowsDownloadUrl}
        macVersion={macVersion}
        windowsVersion={windowsVersion}
      />
      <SiteFooter macVersion={macVersion} windowsVersion={windowsVersion} />
    </main>
  );
}
