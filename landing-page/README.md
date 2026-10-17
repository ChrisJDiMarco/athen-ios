# Athen landing page

Single-file static site for hosting the App Store-required Privacy + Terms URLs.

## Deploy options (cheapest → nicest)

### Option 1 — GitHub Pages (free, 5 min)
```bash
# From repo root
git checkout --orphan gh-pages
git rm -rf .
cp landing-page/index.html .
git add index.html
git commit -m "Initial gh-pages"
git push origin gh-pages
# Then in GitHub repo Settings → Pages → Source: gh-pages branch
# URL becomes: https://<your-username>.github.io/<repo-name>/
```

### Option 2 — Vercel (free, 3 min)
```bash
npm i -g vercel
cd landing-page
vercel --prod
# URL becomes: https://athen-landing-xxx.vercel.app or your custom domain
```

### Option 3 — Cloudflare Pages (free, 3 min)
- Push the `landing-page/` directory to a repo
- Cloudflare dashboard → Pages → Create → Connect to Git → select repo
- Build settings: leave blank, output directory `landing-page`
- Deploy

### Option 4 — Your own domain (recommended for v1)
After any of the above, point your domain (e.g. athen.app) at the deployment via DNS. Update the App Store Connect Privacy + Terms URLs to:
- Privacy: `https://athen.app/#privacy`
- Terms: `https://athen.app/#terms`

## Edit before deploy

Open `index.html` and find/replace:
- `chris@logicoutloud.com` → your real support email if different
- `2026-05-19` → today's effective date (only if you make substantive changes)
- `Commonwealth of Pennsylvania` → your jurisdiction if different

## After deploy

In App Store Connect → App Information:
- **Privacy Policy URL**: `https://<your-host>/#privacy`
- **Terms of Use URL**: `https://<your-host>/#terms`
- **Support URL**: `https://<your-host>/#support`

These three URLs satisfy all of Apple's required-URL fields with a single file.
