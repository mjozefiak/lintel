# Sending mail and invites as the user: OAuth scopes, verification, MCP (2026-11-26)

Scope: a native macOS app, public, outside the Mac App Store, no backend, tokens in Keychain. It sends email and creates calendar events with guests as the user after a click on "Send".

Labels: FACT = stated on an official page, REPORTED = community or third party, INFERENCE = my conclusion. Every claim "checked 2026-11-26". Pages were read through a summarising fetch tool, so numbers are quoted from its extract; re-read the cited page before a decision.

## A. Google

### A1. Scopes and classification

- FACT: `https://www.googleapis.com/auth/gmail.send` ("Send email on your behalf") is listed in the **Sensitive** table of the Gmail scopes page, not Restricted. https://developers.google.com/workspace/gmail/api/auth/scopes
- FACT: Calendar scopes page describes `calendar.events` ("View and edit events on all your calendars"), `calendar.events.owned` ("See, create, change, and delete events on Google calendars you own") and `calendar` but carries no sensitivity column. https://developers.google.com/workspace/calendar/api/auth
- FACT: Google's scope table says sensitive scopes carry a "sensitive" indicator on the Cloud Console consent screen, not on the docs page. https://developers.google.com/identity/protocols/oauth2/scopes
- REPORTED: Nylas lists `calendar.events` as sensitive (verification, no security assessment). https://developer.nylas.com/docs/provider-guides/google/google-verification-security-assessment-guide.md
- INFERENCE: `calendar.events` and `calendar.events.owned` are sensitive, not restricted; confirm in the Cloud Console scope picker (it labels each scope). Prefer `calendar.events.owned` (narrower: only calendars the user owns) and justify "why not a narrower scope" in the review.
- FACT: Restricted scopes (Gmail read/modify, Drive...) are the ones needing the security assessment; neither gmail.send nor calendar scopes are on the restricted list the Cloud support page names. https://support.google.com/cloud/answer/13464325

### A2. Verification for sensitive scopes

FACT (https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification):
- Brand verification first: authorised domain verified in Search Console; app name, support email, home page URL and privacy policy URL accurate on the consent screen.
- Home page: public, describes the app, links to the privacy policy. Store pages and social pages do not count.
- Privacy policy: same domain as the home page, linked from the consent screen, discloses access/use/storage/sharing of Google user data.
- Demo video: unlisted YouTube, English, shows the OAuth grant, the app name on the consent screen, the OAuth client ID in the browser address bar, and what each sensitive scope enables.
- Written justification per scope, and why a narrower scope would not work.
- Exceptions listed: personal use, development/testing projects, internal use, domain-wide installation.
- Timelines on that page: automated brand review "usually a few minutes"; brand result valid 7 days (publish within that window or re-verify); sensitive scope verification "can take up to 10 days".

Other durations (they disagree, so show the range):
- FACT: Google FAQ says (not guaranteed): brand 2-3 business days, sensitive 10 business days, restricted 6 weeks. https://support.google.com/cloud/answer/13463817
- FACT/REPORTED: a mirror of the sensitive-scope page and a search extract quote "3-5 business days" (older wording, seen via developers.google.cn). Not seen on the main page today.
- REPORTED: Nylas says reviews "can take several weeks or longer"; delays come from rejections and back-and-forth. No Reddit or Stack Overflow durations were found in this search. Not found.

CASA / security assessment:
- FACT: applies to restricted scopes only, and only to apps that access that data "from or through a third-party server". Annual re-assessment by an approved assessor; "several weeks". https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- FACT: the sensitive-scope page does not mention CASA. INFERENCE: not required for gmail.send + calendar.events(.owned), and the app has no server anyway. Cost of a CASA assessment: not stated by Google; not researched.

### A3. Running unverified

- FACT: Testing status, External user type: up to **100 test users** listed on the consent screen. Authorisations by a test user (refresh token) expire **7 days** after consent (not for name/email/profile only). https://support.google.com/cloud/answer/15549945 and https://developers.google.com/identity/protocols/oauth2#expiration
- FACT: In production, unverified app using sensitive/restricted scopes: **100 new users in total** after the "unverified app" screen, over the whole project lifetime, cannot be reset; when exhausted sign-in can be disabled. https://support.google.com/cloud/answer/13463817 and https://support.google.com/cloud/answer/15549945
- FACT: refresh-token cap 100 per Google Account per client ID; the oldest is invalidated silently beyond that. https://developers.google.com/identity/protocols/oauth2#expiration
- Installed-app flow, FACT (https://developers.google.com/identity/protocols/oauth2/native-app): desktop apps use loopback redirect `http://127.0.0.1:port` (or `[::1]`), exact redirect URI registered; always use PKCE (S256 recommended); desktop apps are public clients and the client secret is optional and not confidential; custom URI schemes are "no longer supported"; refresh tokens are always returned to installed apps; incremental authorization not supported for installed apps.
- INFERENCE: for macOS, loopback + PKCE + refresh token in Keychain is the supported path; the "Testing" 7-day expiry makes Testing unusable beyond a closed alpha.

### A4. Avoiding verification

- FACT: apps used only inside one Workspace/Cloud Identity organisation can be User type **Internal** (users outside get `org_internal`). https://support.google.com/cloud/answer/13463817 (domain-wide installation still needs verification if sensitive scopes are used, per the sensitive-scope page).
- FACT: personal-use and development/testing exceptions exist (sensitive-scope page). No page found defining "bring your own client" for end users.
- INFERENCE: a "bring your own Google Cloud OAuth client" mode (user creates a project, adds themselves as test user, pastes client ID) avoids Lintel's verification, but the user's own project stays in Testing: 7-day refresh-token expiry unless they publish their own project (for personal use the exception applies, unverified screen shown, 100-user cap irrelevant for one user). Heavy UX; fit for power users only. Not verified in a test.
- INFERENCE: Lintel's own verified client is the only path that gives normal users a clean consent and long-lived tokens. Lead time is days to weeks; the 100-user cap means a closed beta can run unverified first (first 100 users, lifetime), then verification must land before wider release.

## B. Microsoft (Outlook / Microsoft 365)

### B1. Delegated permissions

- FACT: delegated `Mail.Send`: admin consent **not required**; "available for consent in personal Microsoft accounts"; valid for both personal and work/school accounts. https://learn.microsoft.com/en-us/graph/permissions-reference
- FACT: delegated `Calendars.ReadWrite`: AdminConsentRequired **No**; available for consent in personal accounts. Same page.
- FACT: by default users can consent to permissions that do not require admin consent, e.g. to let an app access their mailbox. https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent

### B2. Publisher verification and tenant policy

- FACT: since November 2020, if risk-based step-up consent is enabled, users cannot consent to most newly registered multitenant apps that are not publisher verified, when permissions go beyond sign-in and basic profile and the user is in another tenant; a warning shows "unverified publisher". https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview
- FACT: tenant policy `microsoft-user-default-low` = users may consent only for apps from verified publishers (or registered in the tenant) and only for permissions the admin classified as **low impact**; `microsoft-user-default-legacy` = any permission not needing admin consent, any app. https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent
- FACT: only delegated permissions that do not require admin consent can be classified; classifications are set by the tenant admin (Low, Medium preview, High preview). The page's own example is openid/profile/email/offline_access. https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-permission-classifications
- INFERENCE: Mail.Send is not low impact unless a tenant admin classifies it so; I found no default classification that includes it. In a tenant on the "verified publishers, low impact" policy an unverified app is blocked, the user must ask an admin (admin consent workflow). Verified publisher status therefore matters for work accounts, not for personal ones.
- Personal accounts (outlook.com): FACT: apps registered with a personal Microsoft account cannot be publisher verified; publisher verification concerns Entra tenant consent. INFERENCE: personal accounts consent without it; no Microsoft verification page found for personal-account consent.
- Requirements, FACT: a verified Microsoft AI Cloud Partner Program (Partner One ID, partner global account), app registered in an Entra work/school tenant tied to it, publisher domain set (not onmicrosoft.com), MFA, admin roles in Entra and Partner Center. No fee. "Can be verified in minutes" for those who already meet the requirements; processing "a few minutes". https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview and https://learn.microsoft.com/en-us/entra/identity-platform/mark-app-as-publisher-verified
- Not found: how long creating and verifying the Partner Center (CPP) account itself takes. Treat as unknown (INFERENCE: days, includes organisation verification).

### B3. Public-client auth

- FACT: desktop apps are public clients (no client secret); register the platform "Mobile and desktop"; for macOS Swift/Obj-C the redirect is `msauth.<bundle.id>://auth`; for system browser `http://localhost`; MSAL for iOS and macOS is listed GA; enable "Allow public client flows". https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration
- Authority `common` serves both personal and work accounts (shown in the same page's samples). PKCE use inside MSAL: not stated on that page; MSAL uses the code flow with PKCE (INFERENCE, check the MSAL docs).

## C. MCP route

| Server | Official? | Can send mail? | Verification burden | Maturity |
|---|---|---|---|---|
| Google Gmail MCP `gmailmcp.googleapis.com/mcp/v1` | Official | **No**: 10 tools, only `create_draft`; scopes gmail.readonly/compose/modify | Needs an OAuth client from your own Cloud project (FACT: configure page) so it does NOT avoid verification | Developer Preview |
| Microsoft Mail MCP (Agent 365 / Work IQ, `mcp_MailTools`) | Official | Yes: `sendMail`, `sendDraft`, reply, replyAll | Tenant-level, needs Agent 365/Frontier licence (REPORTED, Microsoft Q&A); not an app-level OAuth shortcut | Preview; Microsoft says the app-specific servers are "for backward compatibility ... not production" and points to Work IQ MCP |
| Zapier MCP (Gmail: Send Email action) | Third party | Yes | Zapier's own Google app does the OAuth; Lintel avoids verification but sends through Zapier cloud, user needs a Zapier account and plan | Commercial, GA; also "Email by Zapier" sends from a zapiermail.com address, 5/day free or 10/hour paid (REPORTED by Zapier page) |
| Composio (Gmail toolkit) | Third party | Gmail toolkit (send not confirmed on the page I read) | Managed auth uses Composio's registered OAuth app (no setup); own app optional; "must be approved for the scopes" if your own | Commercial; Gmail send scope not verified here |
| Workato Gmail MCP, Portkey | Third party | Yes (Portkey lists a send scope) | Custom OAuth profile (Workato) means your own client | Commercial; not checked deeply |
| Fastmail | **No official MCP found**; third-party JMAP servers (e.g. MadLlama25/fastmail-mcp, pyfastmail-mcp) | Yes (send_draft, mail_send_email) | API token, no OAuth app | Hobby projects, "not affiliated" |

Sources: https://developers.google.com/workspace/gmail/api/reference/mcp, https://developers.google.com/workspace/gmail/api/guides/configure-mcp-server, https://learn.microsoft.com/en-us/microsoft-copilot-studio/mcp-mail-tools, https://zapier.com/mcp/gmail, https://docs.composio.dev/docs/authentication/custom-app-vs-managed-app, https://mcpservers.org/servers/MadLlama25/fastmail-mcp, https://pypi.org/project/pyfastmail-mcp/ (all checked 2026-11-26).

- INFERENCE: only third-party aggregators (Zapier, Composio managed) avoid Lintel's own verification, because their verified app is used, at the price of a third-party cloud seeing the mail and of a paid account. Google's official server cannot send and still needs your client; Microsoft's is preview and tenant-licensed. Anthropic's Gmail connector reportedly sends with per-email approval (REPORTED, dragapp comparison) but is not an option for Lintel's own app.
- Calendar events with guests via MCP: not researched here (Google Calendar MCP status not checked).

## D. Order of delivery (INFERENCE)

1. **Open as draft** (mailto / Mail.app, `.ics` file for events): ships first, no OAuth, always the fallback.
2. **Microsoft send-as-user** (MSAL, Mail.Send + Calendars.ReadWrite, personal + work): no admin consent, no Microsoft review for personal accounts and for tenants on the default policy; register one multitenant public client. Add publisher verification (free, but needs a Partner Program account, lead time unknown) before promoting to work accounts, because stricter tenants block unverified apps.
3. **Google send-as-user**: start the sensitive-scope verification early (brand verification, privacy policy and home page on a Lintel domain, demo video, per-scope justification), budget 10 business days plus resubmissions (weeks reported). Meanwhile run the closed beta under the unverified cap (first 100 users, lifetime, cannot be reset; refresh token in Testing expires after 7 days, so use production status, not Testing). Offer "bring your own client" only as an advanced option.
4. **MCP as an extra path**: Zapier/Composio-style third-party servers for users who already have them, behind the same Send approval. Skip Google's official Gmail MCP for sending (no send tool) and Microsoft's Agent 365 server (preview, licence).
5. Decision for the owner: whether 100 lifetime unverified users is enough for beta, and whether to open a Partner Program account now (long pole for Microsoft work accounts).

Open items not found: community-reported Google review durations (no forum data), Partner Center account lead time, Calendar MCP servers, CASA price.
