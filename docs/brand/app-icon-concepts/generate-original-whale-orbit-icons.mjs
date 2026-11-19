import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const outDir = path.join(root, 'docs', 'brand', 'app-icon-concepts');
const chrome = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

const whalePath =
  'M286 392C320 331 383 292 461 286C553 279 636 315 683 379C724 435 737 507 716 572C696 636 648 687 586 711C531 733 468 731 413 707C371 688 337 657 314 620C296 590 284 557 282 523C280 491 282 458 290 426C292 418 294 410 286 392ZM429 455C409 455 393 471 393 491C393 511 409 527 429 527C449 527 465 511 465 491C465 471 449 455 429 455ZM546 592C508 592 473 575 448 546C441 538 430 536 421 542C412 548 410 561 416 569C448 609 494 632 546 632C561 632 576 630 591 626C603 623 609 611 605 600C602 590 591 584 580 587C569 590 558 592 546 592Z';

const tailPath =
  'M705 386C731 337 774 305 826 298C820 349 792 394 748 420C779 425 804 448 815 478C773 492 727 481 696 449C683 435 676 418 676 401C685 403 695 398 705 386Z';

const hugWhalePath =
  'M247 510C247 382 339 276 465 250C591 224 721 279 783 385C802 417 815 452 821 488C837 493 849 508 852 526C855 548 842 568 822 577C801 642 750 696 682 727C593 768 483 758 397 702C313 648 247 585 247 510ZM406 445C386 445 370 461 370 481C370 501 386 517 406 517C426 517 442 501 442 481C442 461 426 445 406 445ZM585 628C539 628 497 606 470 570C462 560 448 558 439 566C430 574 429 588 437 597C473 641 526 667 585 667C609 667 632 662 654 653C666 648 671 634 666 623C661 612 647 607 636 612C620 620 603 628 585 628Z';

const hugTailPath =
  'M777 382C792 317 838 267 900 247C906 323 873 394 812 435C850 437 884 459 903 492C854 527 787 525 739 487C711 464 696 432 696 398C727 407 756 403 777 382Z';

const toolWhalePath =
  'M245 519C245 399 325 296 438 259C551 222 681 258 763 348C796 384 818 428 827 475C846 483 858 501 858 522C858 541 847 558 830 566C811 630 760 681 690 711C599 750 489 735 403 672C325 614 245 593 245 519ZM407 449C388 449 373 464 373 483C373 502 388 517 407 517C426 517 441 502 441 483C441 464 426 449 407 449Z';

const toolTailPath =
  'M754 348C765 274 807 214 872 185C891 264 870 346 816 403C851 398 887 412 912 439C874 486 805 503 746 477C710 462 686 432 678 396C709 396 737 379 754 348Z';

function iconSvg({ file, bgA, bgB, halo, orbA, orbB, orbC, whaleA, whaleB, accent, ringOpacity = 0.96, darkMark = false }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${bgA}"/>
      <stop offset="1" stop-color="${bgB}"/>
    </linearGradient>
    <radialGradient id="halo" cx="50%" cy="44%" r="58%">
      <stop offset="0" stop-color="${halo}" stop-opacity="0.55"/>
      <stop offset="0.52" stop-color="${halo}" stop-opacity="0.18"/>
      <stop offset="1" stop-color="${halo}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="orb" cx="36%" cy="28%" r="72%">
      <stop offset="0" stop-color="${orbA}"/>
      <stop offset="0.52" stop-color="${orbB}"/>
      <stop offset="1" stop-color="${orbC}"/>
    </radialGradient>
    <linearGradient id="whale" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${whaleA}"/>
      <stop offset="1" stop-color="${whaleB}"/>
    </linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="${accent}" stop-opacity="0"/>
      <stop offset="0.25" stop-color="${accent}" stop-opacity="0.9"/>
      <stop offset="0.75" stop-color="${accent}" stop-opacity="0.9"/>
      <stop offset="1" stop-color="${accent}" stop-opacity="0"/>
    </linearGradient>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="18"/>
    </filter>
    <filter id="shadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="26" stdDeviation="28" flood-color="#05070d" flood-opacity="0.35"/>
    </filter>
    <clipPath id="orbClip">
      <circle cx="512" cy="494" r="232"/>
    </clipPath>
  </defs>

  <rect width="1024" height="1024" rx="230" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="230" fill="url(#halo)"/>

  <g filter="url(#shadow)">
    <circle cx="512" cy="494" r="238" fill="url(#orb)"/>
    <g clip-path="url(#orbClip)" opacity="0.35">
      <path d="M286 536C388 460 474 470 575 526C650 568 716 570 794 522" fill="none" stroke="#ffffff" stroke-width="22" stroke-linecap="round"/>
      <path d="M310 605C410 545 492 558 588 606C654 639 718 638 772 604" fill="none" stroke="#ffffff" stroke-width="12" stroke-linecap="round" opacity="0.55"/>
      <circle cx="404" cy="356" r="84" fill="#ffffff" opacity="0.26"/>
    </g>

    <path d="M245 508C288 331 454 225 633 249C742 264 832 328 879 421" fill="none" stroke="url(#accent)" stroke-width="22" stroke-linecap="round" opacity="${ringOpacity}"/>
    <path d="M797 625C733 737 605 798 469 771" fill="none" stroke="url(#accent)" stroke-width="18" stroke-linecap="round" opacity="0.72"/>

    <g transform="rotate(-10 512 512)">
      <path d="${tailPath}" fill="url(#whale)"/>
      <path d="${whalePath}" fill="url(#whale)" fill-rule="evenodd"/>
      <path d="M333 394C379 339 447 315 520 324C610 336 682 407 697 496" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="20" stroke-linecap="round"/>
      <path d="M342 620C391 690 481 724 568 704C624 691 673 655 699 606" fill="none" stroke="#000000" stroke-opacity="0.16" stroke-width="22" stroke-linecap="round"/>
    </g>
  </g>

  <g opacity="${darkMark ? 0.86 : 0.72}">
    <rect x="432" y="776" width="46" height="18" rx="9" fill="#ffffff"/>
    <rect x="489" y="776" width="94" height="18" rx="9" fill="#ffffff"/>
    <rect x="594" y="776" width="30" height="18" rx="9" fill="#ffffff"/>
  </g>

  <metadata>${file}: original DSH concept, no third-party marks</metadata>
</svg>`;
}

function hugIconSvg({ file, bgA, bgB, halo, orbA, orbB, orbC, whaleA, whaleB, accent, inner, darkMark = false }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${bgA}"/>
      <stop offset="1" stop-color="${bgB}"/>
    </linearGradient>
    <radialGradient id="halo" cx="48%" cy="42%" r="62%">
      <stop offset="0" stop-color="${halo}" stop-opacity="0.58"/>
      <stop offset="0.55" stop-color="${halo}" stop-opacity="0.16"/>
      <stop offset="1" stop-color="${halo}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="orb" cx="36%" cy="27%" r="74%">
      <stop offset="0" stop-color="${orbA}"/>
      <stop offset="0.48" stop-color="${orbB}"/>
      <stop offset="1" stop-color="${orbC}"/>
    </radialGradient>
    <linearGradient id="whale" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${whaleA}"/>
      <stop offset="1" stop-color="${whaleB}"/>
    </linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="${accent}" stop-opacity="0"/>
      <stop offset="0.28" stop-color="${accent}" stop-opacity="0.9"/>
      <stop offset="0.74" stop-color="${accent}" stop-opacity="0.9"/>
      <stop offset="1" stop-color="${accent}" stop-opacity="0"/>
    </linearGradient>
    <filter id="shadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="30" stdDeviation="34" flood-color="#02040a" flood-opacity="0.38"/>
    </filter>
    <clipPath id="innerClip">
      <circle cx="532" cy="506" r="202"/>
    </clipPath>
  </defs>

  <rect width="1024" height="1024" rx="230" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="230" fill="url(#halo)"/>

  <g filter="url(#shadow)">
    <circle cx="532" cy="506" r="214" fill="url(#orb)"/>
    <g clip-path="url(#innerClip)" opacity="0.5">
      <path d="M330 529C423 458 505 463 604 522C678 566 743 565 812 512" fill="none" stroke="#ffffff" stroke-width="19" stroke-linecap="round" opacity="0.58"/>
      <path d="M360 607C454 553 528 562 618 608C675 637 733 636 787 605" fill="none" stroke="#ffffff" stroke-width="11" stroke-linecap="round" opacity="0.42"/>
      <circle cx="420" cy="342" r="74" fill="#ffffff" opacity="0.28"/>
    </g>

    <path d="M270 502C299 341 442 231 606 244C734 254 836 335 882 450" fill="none" stroke="url(#accent)" stroke-width="20" stroke-linecap="round"/>
    <path d="M812 619C746 737 616 800 474 773" fill="none" stroke="url(#accent)" stroke-width="17" stroke-linecap="round" opacity="0.72"/>

    <g transform="rotate(-8 548 512)">
      <path d="${hugTailPath}" fill="url(#whale)"/>
      <path d="${hugWhalePath}" fill="url(#whale)" fill-rule="evenodd"/>
      <path d="M310 409C357 331 443 287 539 293C646 300 735 374 766 472" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="22" stroke-linecap="round"/>
      <path d="M337 632C402 718 515 751 621 716C689 694 743 647 775 585" fill="none" stroke="#000000" stroke-opacity="0.16" stroke-width="24" stroke-linecap="round"/>
    </g>
  </g>

  <g opacity="${darkMark ? 0.86 : 0.72}">
    <rect x="438" y="790" width="42" height="16" rx="8" fill="#ffffff"/>
    <rect x="492" y="790" width="92" height="16" rx="8" fill="#ffffff"/>
    <rect x="596" y="790" width="28" height="16" rx="8" fill="#ffffff"/>
  </g>

  <metadata>${file}: original DSH concept, no third-party marks</metadata>
</svg>`;
}

function toolIconSvg({ file, bgA, bgB, halo, orbA, orbB, orbC, whaleA, whaleB, accent, darkMark = false }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${bgA}"/>
      <stop offset="1" stop-color="${bgB}"/>
    </linearGradient>
    <radialGradient id="halo" cx="48%" cy="42%" r="64%">
      <stop offset="0" stop-color="${halo}" stop-opacity="0.55"/>
      <stop offset="0.56" stop-color="${halo}" stop-opacity="0.15"/>
      <stop offset="1" stop-color="${halo}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="orb" cx="37%" cy="27%" r="76%">
      <stop offset="0" stop-color="${orbA}"/>
      <stop offset="0.5" stop-color="${orbB}"/>
      <stop offset="1" stop-color="${orbC}"/>
    </radialGradient>
    <linearGradient id="whale" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${whaleA}"/>
      <stop offset="1" stop-color="${whaleB}"/>
    </linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="${accent}" stop-opacity="0"/>
      <stop offset="0.26" stop-color="${accent}" stop-opacity="0.95"/>
      <stop offset="0.74" stop-color="${accent}" stop-opacity="0.95"/>
      <stop offset="1" stop-color="${accent}" stop-opacity="0"/>
    </linearGradient>
    <filter id="shadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="32" stdDeviation="34" flood-color="#02040a" flood-opacity="0.4"/>
    </filter>
    <clipPath id="innerClip">
      <circle cx="540" cy="505" r="196"/>
    </clipPath>
  </defs>

  <rect width="1024" height="1024" rx="230" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="230" fill="url(#halo)"/>

  <g filter="url(#shadow)">
    <circle cx="540" cy="505" r="204" fill="url(#orb)"/>
    <g clip-path="url(#innerClip)" opacity="0.48">
      <path d="M342 526C428 461 509 464 600 518C676 564 737 564 802 516" fill="none" stroke="#ffffff" stroke-width="17" stroke-linecap="round" opacity="0.56"/>
      <path d="M365 603C448 554 521 561 608 604C665 632 719 632 771 605" fill="none" stroke="#ffffff" stroke-width="10" stroke-linecap="round" opacity="0.42"/>
      <circle cx="429" cy="348" r="66" fill="#ffffff" opacity="0.27"/>
    </g>

    <path d="M281 497C319 345 459 247 612 264C727 277 819 350 862 451" fill="none" stroke="url(#accent)" stroke-width="19" stroke-linecap="round"/>
    <path d="M806 618C739 727 617 783 485 758" fill="none" stroke="url(#accent)" stroke-width="16" stroke-linecap="round" opacity="0.72"/>

    <g transform="rotate(-7 550 512)">
      <path d="${toolTailPath}" fill="url(#whale)"/>
      <path d="${toolWhalePath}" fill="url(#whale)" fill-rule="evenodd"/>
      <path d="M316 405C360 333 441 292 531 297C633 303 717 371 748 463" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="21" stroke-linecap="round"/>
      <path d="M344 631C403 705 500 734 595 709C658 693 710 655 744 603" fill="none" stroke="#000000" stroke-opacity="0.15" stroke-width="22" stroke-linecap="round"/>
      <rect x="550" y="598" width="54" height="18" rx="9" fill="${accent}" opacity="0.78"/>
    </g>
  </g>

  <g opacity="${darkMark ? 0.84 : 0.7}">
    <rect x="442" y="790" width="40" height="16" rx="8" fill="#ffffff"/>
    <rect x="494" y="790" width="90" height="16" rx="8" fill="#ffffff"/>
    <rect x="596" y="790" width="26" height="16" rx="8" fill="#ffffff"/>
  </g>

  <metadata>${file}: original DSH concept, no third-party marks</metadata>
</svg>`;
}

const variants = [
  {
    file: 'dsh-icon-concept-01-deep-orbit.png',
    bgA: '#101828', bgB: '#05070d', halo: '#43c7ff',
    orbA: '#79ecff', orbB: '#1aa8d8', orbC: '#095f9e',
    whaleA: '#f7fbff', whaleB: '#b9d4e6', accent: '#55e0ff',
  },
  {
    file: 'dsh-icon-concept-02-glass-blue.png',
    bgA: '#e8f6ff', bgB: '#b7dcf4', halo: '#ffffff',
    orbA: '#ffffff', orbB: '#75d6ff', orbC: '#1680c8',
    whaleA: '#102033', whaleB: '#243f5a', accent: '#0e7fd0',
    darkMark: true,
  },
  {
    file: 'dsh-icon-concept-03-execution-green.png',
    bgA: '#071511', bgB: '#020605', halo: '#54f2a9',
    orbA: '#c8ffe4', orbB: '#41d987', orbC: '#08764a',
    whaleA: '#f6fff9', whaleB: '#9ad9bd', accent: '#60f0a8',
  },
  {
    file: 'dsh-icon-concept-04-graphite-terminal.png',
    bgA: '#272b31', bgB: '#0d1014', halo: '#a8b7c9',
    orbA: '#e9f1f7', orbB: '#8fa8bb', orbC: '#435766',
    whaleA: '#101318', whaleB: '#313a43', accent: '#e7eef5',
    darkMark: true,
  },
];

const hugVariants = [
  {
    file: 'dsh-icon-concept-05-deep-hug.png',
    bgA: '#111827', bgB: '#05070d', halo: '#42caff',
    orbA: '#a8f2ff', orbB: '#2cb5e5', orbC: '#075d99',
    whaleA: '#f7fbff', whaleB: '#a9c6d8', accent: '#55e0ff',
  },
  {
    file: 'dsh-icon-concept-06-frost-hug.png',
    bgA: '#eef8ff', bgB: '#bdddf0', halo: '#ffffff',
    orbA: '#ffffff', orbB: '#82dcff', orbC: '#147cc4',
    whaleA: '#0d1d2c', whaleB: '#263d52', accent: '#1387d6',
    darkMark: true,
  },
];

const toolVariants = [
  {
    file: 'dsh-icon-concept-07-tool-whale-dark.png',
    bgA: '#111827', bgB: '#05070d', halo: '#43c7ff',
    orbA: '#a5f0ff', orbB: '#26aede', orbC: '#075d99',
    whaleA: '#f6fbff', whaleB: '#a9c5d6', accent: '#55e0ff',
  },
  {
    file: 'dsh-icon-concept-08-tool-whale-light.png',
    bgA: '#eef8ff', bgB: '#bdddf0', halo: '#ffffff',
    orbA: '#ffffff', orbB: '#82dcff', orbC: '#147cc4',
    whaleA: '#0c1c2a', whaleB: '#263d52', accent: '#1287d5',
    darkMark: true,
  },
];

await mkdir(outDir, { recursive: true });

for (const variant of variants) {
  const svg = iconSvg(variant);
  const base = variant.file.replace(/\.png$/, '');
  const svgPath = path.join(outDir, `${base}.svg`);
  const htmlPath = path.join(outDir, `${base}.html`);
  const pngPath = path.join(outDir, variant.file);

  await writeFile(svgPath, svg, 'utf8');
  await writeFile(htmlPath, `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;width:1024px;height:1024px;overflow:hidden;background:transparent}svg{display:block}</style>${svg}`, 'utf8');

  await new Promise((resolve, reject) => {
    execFile(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--window-size=1024,1024',
      `--screenshot=${pngPath}`,
      `file:///${htmlPath.replaceAll('\\\\', '/')}`,
    ], { timeout: 20000 }, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
  });

  console.log(variant.file);
}

for (const variant of hugVariants) {
  const svg = hugIconSvg(variant);
  const base = variant.file.replace(/\.png$/, '');
  const svgPath = path.join(outDir, `${base}.svg`);
  const htmlPath = path.join(outDir, `${base}.html`);
  const pngPath = path.join(outDir, variant.file);

  await writeFile(svgPath, svg, 'utf8');
  await writeFile(htmlPath, `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;width:1024px;height:1024px;overflow:hidden;background:transparent}svg{display:block}</style>${svg}`, 'utf8');

  await new Promise((resolve, reject) => {
    execFile(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--window-size=1024,1024',
      `--screenshot=${pngPath}`,
      `file:///${htmlPath.replaceAll('\\\\', '/')}`,
    ], { timeout: 20000 }, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
  });

  console.log(variant.file);
}

for (const variant of toolVariants) {
  const svg = toolIconSvg(variant);
  const base = variant.file.replace(/\.png$/, '');
  const svgPath = path.join(outDir, `${base}.svg`);
  const htmlPath = path.join(outDir, `${base}.html`);
  const pngPath = path.join(outDir, variant.file);

  await writeFile(svgPath, svg, 'utf8');
  await writeFile(htmlPath, `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;width:1024px;height:1024px;overflow:hidden;background:transparent}svg{display:block}</style>${svg}`, 'utf8');

  await new Promise((resolve, reject) => {
    execFile(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--window-size=1024,1024',
      `--screenshot=${pngPath}`,
      `file:///${htmlPath.replaceAll('\\\\', '/')}`,
    ], { timeout: 20000 }, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
  });

  console.log(variant.file);
}
