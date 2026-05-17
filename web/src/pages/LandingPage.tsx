import SiteNav from "@/components/sections/SiteNav";
import Hero from "@/components/sections/Hero";
import DemoStrip from "@/components/sections/DemoStrip";
import FeaturesGrid from "@/components/sections/FeaturesGrid";
import SpecStrip from "@/components/sections/SpecStrip";
import FinalCTA from "@/components/sections/FinalCTA";
import SiteFooter from "@/components/sections/SiteFooter";

interface LandingPageProps {
  downloadUrl: string;
  version: string;
}

export default function LandingPage({
  downloadUrl,
  version,
}: LandingPageProps) {
  return (
    <main className="relative min-h-screen">
      <SiteNav downloadUrl={downloadUrl} />
      <Hero downloadUrl={downloadUrl} version={version} />
      <DemoStrip />
      <FeaturesGrid />
      <SpecStrip />
      <FinalCTA downloadUrl={downloadUrl} version={version} />
      <SiteFooter version={version} />
    </main>
  );
}
