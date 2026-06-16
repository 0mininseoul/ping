const SITE_ORIGIN = 'https://0minping.vercel.app';
const SITE_NAME = 'Ping';
const OG_IMAGE_PATH = '/app-icon.png';
const OG_IMAGE_WIDTH = 1024;
const OG_IMAGE_HEIGHT = 1024;

export const defaultOpenGraph = {
  origin: SITE_ORIGIN,
  siteName: SITE_NAME,
  title: 'Ping - 3초 영상 메시지',
  description: 'Mac에서 키보드 단축키로 3초 영상 메시지를 보내는 메뉴바 앱입니다.',
  imageURL: absoluteURL(OG_IMAGE_PATH),
  imageWidth: OG_IMAGE_WIDTH,
  imageHeight: OG_IMAGE_HEIGHT,
};

export function buildInviteOpenGraphHTML(token: string): string {
  const safeToken = token.trim();
  const encodedToken = encodeURIComponent(safeToken);
  const canonicalURL = absoluteURL(`/invite/${encodedToken}`);
  const deepLinkURL = `ping://invite/${encodedToken}`;
  const title = 'Ping 초대 링크';
  const description = 'Ping에서 3초 영상 메시지를 주고받으세요.';

  return `<!doctype html>
<html lang="ko">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${escapeHTML(title)}</title>
    ${openGraphMetaTags({
      title,
      description,
      url: canonicalURL,
      imageURL: defaultOpenGraph.imageURL,
    })}
    <link rel="canonical" href="${escapeHTML(canonicalURL)}" />
    <link rel="icon" type="image/png" href="/app-icon.png" />
  </head>
  <body>
    <main>
      <h1>${escapeHTML(title)}</h1>
      <p>${escapeHTML(description)}</p>
      <p><a href="${escapeHTML(deepLinkURL)}">Ping에서 열기</a></p>
      <p><a href="${defaultOpenGraph.origin}">Ping 설치하기</a></p>
    </main>
  </body>
</html>
`;
}

function openGraphMetaTags(input: {
  title: string;
  description: string;
  url: string;
  imageURL: string;
}): string {
  const title = escapeHTML(input.title);
  const description = escapeHTML(input.description);
  const url = escapeHTML(input.url);
  const imageURL = escapeHTML(input.imageURL);

  return `<meta name="description" content="${description}" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="${escapeHTML(defaultOpenGraph.siteName)}" />
    <meta property="og:title" content="${title}" />
    <meta property="og:description" content="${description}" />
    <meta property="og:url" content="${url}" />
    <meta property="og:image" content="${imageURL}" />
    <meta property="og:image:secure_url" content="${imageURL}" />
    <meta property="og:image:type" content="image/png" />
    <meta property="og:image:width" content="${defaultOpenGraph.imageWidth}" />
    <meta property="og:image:height" content="${defaultOpenGraph.imageHeight}" />
    <meta name="twitter:card" content="summary" />
    <meta name="twitter:title" content="${title}" />
    <meta name="twitter:description" content="${description}" />
    <meta name="twitter:image" content="${imageURL}" />`;
}

function absoluteURL(path: string): string {
  return new URL(path, SITE_ORIGIN).toString();
}

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
