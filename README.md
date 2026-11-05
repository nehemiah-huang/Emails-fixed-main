# Edan website

The public website and member space for Edan. It is a static multi-page site (plain HTML, CSS and JavaScript) backed by Supabase for accounts, memberships, admin tools, Stay bookings and the community chat. Paystack handles membership and Stay payments, and Supabase Edge Functions handle the server-side payment steps.

---

## 0. Quick start

1. Get the code from GitHub (section 1).
2. Run it on your computer (section 2), or deploy it to Vercel (section 3).
3. Make sure the Supabase project has its migrations applied and its secrets set (sections 4 and 5).

---

## 1. Getting the code from GitHub

Requirements: Git and a GitHub account with access to the repository.

```bash
git clone https://github.com/<your-account>/<your-repo>.git
cd <your-repo>
```

To get later changes, run `git pull` inside the project folder.

Never commit a `.env` file. It is listed in `.gitignore` and must stay on your computer only.

---

## 2. Running locally

### Option A: Docker (closest to the live site)

Requirements: Docker Desktop (or Docker Engine on Linux).

```bash
docker build -t edan-site .
docker run --rm -p 8080:80 edan-site
```

Open http://localhost:8080 in your browser.

The image is an nginx web server that serves the project files as they are. `.dockerignore` keeps `.env`, `supabase/`, `node_modules/` and `.git` out of the image.

### Option B: Node.js (for development)

Requirements: Node.js 20 or newer.

```bash
npm install
npm run dev        # development server with live reload
npm run build      # production build into dist/
npm run preview    # serve the built dist/ folder
```

The Vite build only bundles `index.html`. The other pages (`/gather/`, `/members/`, `/dashboard/` and so on) are plain files, so use Docker or any static file server when you need every page to work. Option B is useful for working on the homepage; for the full site, use Option A or a static server such as `npx serve .` from the project folder.

### Important: the site must be opened over HTTP

Pages load their shared header and footer through `js/include.js`, which fetches partial files. Opening `index.html` directly from disk (`file://`) will not show the header or footer. Always use a web server.

---

## 3. Deploying to Vercel

The site is static, so Vercel only needs to serve the files.

1. In Vercel, choose **Add New > Project** and import the GitHub repository.
2. Set **Framework Preset** to **Other**.
3. Leave **Build Command** empty. Vercel would otherwise run the Vite build, which only outputs the homepage.
4. Set **Output Directory** to `.` (the project root).
5. Click **Deploy**.

Every push to the main branch on GitHub then redeploys the site automatically. No secrets go into Vercel: the browser connects to Supabase with the public key already in the code, and server secrets stay in Supabase.

After the first deploy, add the Vercel domain to the allowed redirect URLs in Supabase (Authentication, URL Configuration), so sign-in and password reset links return to the live site.

---

## 4. Connecting to Supabase

The site talks to one Supabase project: `https://jxokngyavfuaodabskko.supabase.co`. This is the project that holds the Stay booking functions, the membership tables and the Edge Functions. Earlier versions of the site pointed at a different project (`qavarsxjqxogfilpgyxn`) that is no longer used.

The project URL and its publishable (anon) key are written directly in these files, and they must match each other and the project above:

- `js/supabase-client.js`
- `js/account.js`
- `js/members.js`
- `js/members-chat.js`
- `js/nav.js`

The publishable key is designed to be public. Access control is enforced by Row Level Security in the database, not by hiding the key. The key for this project is the anon key shown under Project Settings, API in the Supabase dashboard.

To use a different Supabase project, change the URL and key in all five files, then apply the migrations in `supabase/migrations/` in filename order (with the Supabase CLI, `supabase db push`, or by pasting each file into the Supabase SQL editor). Then deploy the Edge Functions and set their secrets (see below). Check that the Stay function exists before testing: `stay_room_availability` should appear under Database, Functions.

### Server-side secrets

The Edge Functions in `supabase/functions/` need these secrets set in your Supabase project (Project Settings, Edge Functions, Secrets):

| Secret | Used by | Purpose |
|---|---|---|
| `PAYSTACK_SECRET_KEY` | `paystack-webhook`, `stay-payment`, `stay-paystack-webhook` | Checks webhook signatures, starts Stay checkouts and verifies payments with Paystack |
| `RESEND_API_KEY` | `paystack-webhook` | Sends the payment receipt email |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically to Edge Functions.

Deploy the functions with the Supabase CLI (`supabase functions deploy <name>`) and keep the `verify_jwt` settings in `supabase/config.toml`. `paystack-webhook` and `stay-paystack-webhook` are public because Paystack calls them. `payment-receipt` and `stay-payment` require a signed-in user; `stay-payment` also checks the user itself.

### Paystack

- Stay checkout: the server gets a checkout access code from Paystack for each booking, so no public key is needed in the browser. Use a **test** secret key while testing.
- Membership checkout: the client needs a Paystack public key (`pk_...`) in `js/gather.js` (the `PAYSTACK_PUBLIC_KEY` constant). It is currently a placeholder, so online membership payment is disabled until a real key is added.
- Webhooks: in the Paystack dashboard, set the webhook URL to `https://<your-project>.supabase.co/functions/v1/paystack-webhook` for memberships, and to `https://<your-project>.supabase.co/functions/v1/stay-paystack-webhook` for Stay bookings.

---

## 5. Roles

- **Visitor:** can browse all public pages.
- **Member:** a signed-in user. Can apply for membership, pay, download their receipt, and open the member space.
- **Active member:** a member whose membership has been approved by an admin and has not expired. Gets the member benefits and the community chat.
- **Admin:** a user whose ID is listed in the `admins` table. Gets the Dashboard link and can manage videos, applications, Stay bookings and rooms.
- **Making someone an admin:** the person first creates an account on `/login/` with the email they will use. Then the database owner adds that account's user ID to the `admins` table (Supabase Table Editor, or an SQL insert). The account must exist in the same Supabase project the site uses. An account created in a different project, or before the site was connected, does not count and must be created again here.

Admin status and membership are enforced in the database. The page checks in `js/` only decide what to show.

---

## 6. Page-by-page guide

Paths are relative to the site root.

### Home (`/`, `index.html`)
- Full-screen hero video from the `site-videos` storage bucket.
- `js/video-views.js` records one row in `video_views` the first time the hero video starts playing.
- Public. No sign-in needed.

### About (`/about/`)
- Founder and team profiles, story chapters and the circular-design section.
- `js/behind-scenes.js` runs decorative sketch animations when sections scroll into view.
- Static content, no backend.

### Login (`/login/`)
- The live sign-in page. The older `/account/` page still exists and runs the same script, but nothing on the site links to it anymore.
- Password reset emails return here, and the page then shows a "Choose a new password" form.
- **Sign up:** name, email, password (at least 8 characters, entered twice). Creates a Supabase account and sends a confirmation email.
- **Sign in:** email and password. Redirects to the membership page if a plan was chosen, or to the stay page otherwise.
- **Forgot password:** sends a reset email that returns to `/login/?mode=recovery`. That page then shows a "Choose a new password" form. The email is only sent if the address has an account in the connected Supabase project (Authentication, Users). Supabase does not say so on screen for unknown addresses.
- The `?plan=monthly` or `?plan=annual` parameter carries the chosen plan through sign-in to the Gather page.
- The `?next=` parameter sends the guest back after sign-in. Only paths under `/stay/` are accepted.

The older `/account/` page's sign-up form does not match its script (no confirm-password field, different name field), so sign-up there always fails. Use `/login/`.

### Gather (`/gather/`): membership
- Shows two plans: Monthly (GH₵1000 per month) and Annual (GH₵8000 per year).
- Clicking a plan without a session sends the visitor to `/login/?plan=...`. Clicking with a session opens the application dialog.
- Payment flow: see section 7.1.
- Scripts: `js/gather.js`, Paystack's inline checkout script.

### Stay (`/stay/`)
- Marketing page with a booking dialog for dates, guests and rate. Rooms: room only GH₵650 per night, with breakfast GH₵700 per night. Up to two guests, minimum one night, check-in 3:00 PM, check-out 11:00 AM.
- The dialog shows nights times the rate for display (rates are also set in the script). The database sets the price that is actually charged. Check-in cannot be in the past.
- Guests check live availability, pick a free room, enter their details and pay through the Paystack checkout window (section 7.6). A chosen room is kept in the browser's session storage only while the guest signs in, then cleared when the selection resumes.
- The booking status panel also opens when Paystack returns the guest to `/stay/?stay_booking=...`.
- Scripts: `js/stay.js` (dates and room list), `js/stay-checkout.js` (guest details and payment), `js/stay-api.js` (calls to the database and Edge Functions). Paystack's inline checkout script is loaded on the page.

### Stay confirmation (`/stay/confirmation.html`)
- Shown after a successful payment, and at the Paystack callback address. It checks the payment with Paystack, then shows the booking details and a payment receipt (amount paid, date and time paid, Paystack reference). Guests can print the receipt.
- Only the booking's own guest can see it. If the guest is signed out, the page asks them to sign in first and returns them here.
- Pending or failed bookings show a status message instead of a receipt.
- Scripts: `js/stay-confirmation.js`, `js/stay-format.js`, `css/pages/stay-confirmation.css`.

### Eat (`/eat/`)
- Café menu with category filters, a featured carousel and a basket.
- Menu items and prices are sample data in `js/eat.js`.
- The basket lives in memory and is lost on reload.
- The checkout form collects name, phone and dine-in or takeaway details. Online payment is marked as not yet enabled.
- Nothing is sent to the backend from this page. Check `js/eat.js` before relying on checkout.

### Grow (`/grow/`)
- Garden and living-lab marketing page with static images and field notes.
- No script beyond the shared header and footer, no backend.

### Labs (`/labs/`)
- Interactive four-field map (sonic, ground, AI, fabric) with tabs and a readout. Script: `js/labs.js`.
- Known bug: the script looks for an element with the ID `readout-link`, which is not on the page. This throws an error after the text updates, so the "Enter this lab" link is not set and keyboard focus does not move. The map still works visually.
- Dossier fields still say "to be confirmed".

### Contact (`/contact/`)
- Contact details and an enquiry form that is posted to FormSubmit, which emails the address set in the form. The address is currently hardcoded in the page. Confirm it before launch.
- Social links and some contact details are still placeholders.
- Script: `js/contact.js`.

### Members (`/members/`)
- Requires a session. Without one, the visitor is sent to `/login/?next=members` and returns here after signing in.
- Shows the member's tier and status. Member sections are hidden unless the membership is active and not expired (`js/members.js`).
- The page has five sections, in this order: 01 Community (chat), 02 In Process (behind the scenes photo), 03 Gather (monthly gatherings), 04 Annual Members bonus videos, 05 Annual Members appointments.
- Sections 04 and 05 are for annual members only. Monthly members see a locked note in their place.
- Gatherings (`member_gatherings`) and bonus videos (`member_bonus_videos`) are loaded from the database (`js/members-content.js`). Each has a title, description, sort order, and optional image, link, or video path. Video files are referenced by their path, which is stored with each bonus video in the database.
- Admins manage gatherings and bonus videos directly in the database for now. A dashboard screen for these is not built yet.
- **Receipt:** if the member has a successful payment, a "Download receipt (PDF)" button appears. It calls the `payment-receipt` Edge Function for the most recent successful payment.
- **Community chat:** a realtime message board for active members (`js/members-chat.js`). Members pick a username (3 to 24 letters, numbers or underscores), then post messages of up to 1000 characters. New messages appear live. Chat access is enforced by the database (`member_chat_messages` policies use `is_active_member`).

### Dashboard (`/dashboard/`), admin only
- Shows the team dashboard: totals for members, homepage video views and video uploads.
- **Homepage video:** an admin uploads an MP4 up to 50 MB. It replaces the file in the `site-videos` bucket and is logged in `video_uploads`.
- **Applications:** lists membership applications. Review opens a dialog to set the tier and start and end dates, then approve or reject. Approval sets the member to active. Rejection asks for confirmation first.
- **Members:** lists the 100 most recent memberships.
- **Bookings:** lists Stay bookings with Upcoming (not yet checked out), Past and All views, search by name, email or reference, and an Add booking button for phone or WhatsApp bookings. Opening a booking shows its details. Confirmed bookings can be checked in once the arrival date has arrived (**Check in guest**, which records the time and shows the booking as Checked in), marked completed when the guest leaves, or cancelled to free the dates.
- **Rooms and blocked dates:** add rooms, close or reopen them for new bookings, and block dates for maintenance or team use. A block cannot cover dates that already have a confirmed booking.
- Scripts: `js/admin.js`, `js/admin-memberships.js`, `js/admin-bookings.js`, `js/admin-availability.js`, `js/admin-table.js`.
- Non-admins see an "access restricted" message. The real protection is the database, so admin actions still fail for non-admins even if the page is changed.

---

## 7. How the algorithms work

### 7.1 Membership payment (end to end)

1. A signed-in visitor chooses a plan on `/gather/` and fills in the application dialog.
2. `js/gather.js` inserts a row into `membership_applications` with status `pending`, the plan, and the applicant's email. Row Level Security only allows this for the signed-in user's own application.
3. The script builds a unique reference (`edan-<plan>-<uuid>`) and opens the Paystack checkout. The amount is set in the browser.
4. Paystack sends a `charge.success` event to `paystack-webhook`.
5. The webhook checks the request signature (HMAC-SHA512 of the raw body with the secret key). Requests with a bad signature are rejected with 401.
6. The webhook stores a hash of the request body in `paystack_events`. Repeat deliveries of the same event are then recognised and ignored.
7. The webhook asks Paystack to verify the transaction. Only a verified `success` status is accepted.
8. The `record_paystack_event` database function locks the matching `payment_transactions` row. It records success only if the row has not already succeeded and the amount and currency match. This is what prevents duplicate or fake payments from being recorded twice.
9. On success, the webhook sends a receipt email once. A conditional update sets `receipt_sent_at` first, so two deliveries cannot both send it. If sending fails, the timestamp is cleared so the next delivery can retry.

Payment never approves a membership. An admin still reviews the application and approves it on the dashboard, which sets the membership dates.

**Current gap:** nothing in this repository creates the `payment_transactions` row that step 8 needs. Until a server step (or an insert from the checkout) creates a `pending` row with the reference, the webhook returns `unmatched` and no payment is recorded. This must be built before live payments work.

### 7.2 Receipt download

1. The member page finds the latest successful payment for the signed-in user.
2. Clicking the button sends the user's session token to `payment-receipt`.
3. The function asks Supabase Auth who the token belongs to, then loads only that user's successful payment.
4. It returns a PDF with the plan, applicant email, application date, amount, payment date and reference.

### 7.3 Admin approval

1. The dashboard checks `is_edan_admin()`. Non-admins see the restricted message.
2. Approve calls `approve_membership_application` with the tier and dates. The database confirms the caller is an admin, then sets the membership to active.
3. Reject calls `reject_membership_application` in the same way.

### 7.4 Homepage video

1. An admin picks an MP4 under 50 MB. The browser checks the type and size.
2. The file is uploaded to `site-videos/hero/edan-hero.mp4`, replacing the old one.
3. A row is added to `video_uploads`. The homepage shows the new video after its cache expires, about a minute.

### 7.5 Community chat

1. The chat checks the member's status in `memberships`.
2. It loads the last 60 messages and the usernames from `member_chat_profiles`.
3. New messages arrive through a realtime subscription on `member_chat_messages`.
4. Messages are inserted with the user's ID and shown as plain text.

### 7.6 Stay room booking (end to end)

1. The guest chooses dates, guests and a rate, then clicks Check availability. `js/stay.js` asks the database for free rooms (`stay_room_availability`). A room is free when no confirmed or completed stay overlaps the dates, no unexpired hold overlaps them, and no closure from the dashboard covers them.
2. Choosing a room while signed out saves the choice in the browser and sends the guest to `/login/`. After signing in, they return to `/stay/?resume=1` and the choice continues.
3. The guest enters name, email and phone, then clicks Continue to payment. `create_stay_hold` creates a `pending_payment` booking that holds the room for 15 minutes. The database sets the price (GH₵650 room only, GH₵700 with breakfast, per night).
4. `stay-payment` (action `initialize`) locks the booking, re-checks the dates (`prepare_stay_payment`), and asks Paystack to start a transaction with reference `EDNSTAY-...`, the amount in pesewas and currency GHS. It saves Paystack's access code on the booking. Repeated requests reuse the saved code.
5. `js/stay-checkout.js` opens Paystack's checkout window on the page with that access code. If the window is closed, Continue to payment reopens it while the hold lasts.
6. Paystack sends `charge.success` to `stay-paystack-webhook`. The webhook checks the HMAC-SHA512 signature, logs the event in `stay_payment_events` (repeats are harmless), verifies the transaction with Paystack, and calls `confirm_stay_payment`. That function confirms the booking only if the reference, amount (total x 100 pesewas), currency and dates still match.
7. If the amount or currency does not match, or a date conflict appears, the booking is cancelled and marked Refund required. No refund is issued automatically; an admin must refund it.
8. After a successful checkout window, the guest is taken to `/stay/confirmation.html?stay_booking=...`. That page asks `stay-payment` (action `verify`) to check with Paystack directly, so the guest sees the result without waiting for the webhook. It then loads the booking through `get_own_stay_confirmation` and shows the receipt.
9. A hold that is not paid within 15 minutes becomes `payment_failed` and releases the room.

---

## 8. Database overview

| Table | Purpose | Who can read | Who can write |
|---|---|---|---|
| `admins` | Admin user IDs | Own row only | Nobody from the client |
| `memberships` | One membership per member | Own row; admins | Only the approval functions |
| `membership_applications` | Applications from `/gather/` | Own rows; admins | Own rows, insert only, status must be pending |
| `payment_transactions` | One row per payment | Own rows; admins | Server only |
| `paystack_events` | Webhook log for duplicate detection | Nobody from the client | Server only |
| `stay_rooms` | Bookable rooms | Admins | Admins (rename, open or close) |
| `stay_bookings` | Stay reservations, holds and payments | Own bookings (guests); admins | Server (online bookings); admins (manual bookings, status changes) |
| `stay_room_blocks` | Dates a room is closed | Admins | Admins |
| `stay_payment_events` | Stay webhook log | Nobody from the client | Server only |
| `member_chat_profiles` | Chat usernames | Signed-in members | Own row only, active members |
| `member_chat_messages` | Community chat messages (realtime) | Active members (`is_active_member`) | Own messages, active members |
| `member_gatherings` | Monthly gatherings shown in section 03 | Active members | Admins |
| `member_bonus_videos` | Annual bonus videos shown in section 04 | Annual members | Admins |
| `video_views` | Homepage video plays | Admins | Anyone (insert only) |
| `video_uploads` | Admin video upload log | Admins | Admins |
| `site-videos` (bucket) | Homepage video file | Public | Admins |

Functions: `is_edan_admin`, `approve_membership_application`, `reject_membership_application` (admins), `record_paystack_event` (server only), `is_active_member(tiers)` (checks the signed-in user's own membership tier and status, used by the member tables' access rules).

Member content access is enforced in the database. Gatherings are readable by active members of either tier. Bonus videos are readable only by active annual members. Appointment booking is not built yet, so section 05 shows a disabled button.

Stay functions: `stay_room_availability` (anyone), `create_stay_hold` and `get_own_stay_confirmation` (signed-in guests, own bookings only), `admin_create_manual_booking`, `admin_block_room`, `admin_set_booking_status` and `admin_check_in_booking` (admins; check-in is recorded in `stay_bookings.checked_in_at`), and `prepare_stay_payment`, `confirm_stay_payment` and `mark_stay_payment_failed` (server only).

Stay rooms are data, not schema. Migrations create the tables only. The five sample rooms named `001` to `005` were added directly in the database for testing. On a fresh project, add rooms from the Dashboard (Rooms and blocked dates) or with an SQL insert into `stay_rooms`.

The member chat and Members content tables are created by the `members_community_gatherings_and_bonus_videos` migration. The `members_active_member_helper_invoker` migration then changes the `is_active_member` helper so it runs with the caller's permissions. Both are in `supabase/migrations/`, so a fresh project gets them when migrations are applied in order.

---

## 9. Project layout

```
index.html              homepage
about/ account/ contact/ dashboard/ eat/ gather/ grow/ labs/ login/ members/ stay/
css/                    shared styles (base, tokens, footer) and css/pages/ per page
js/                     browser scripts, one per page or feature
partials/               shared header and footer
images/                 photos and graphics
supabase/migrations/    database schema, in filename order
supabase/functions/     Edge Functions: paystack-webhook, payment-receipt, stay-payment, stay-paystack-webhook
supabase/config.toml    Edge Function settings
Dockerfile              container image for the static site
.dockerignore           files kept out of the container image
```

---

## 10. Testing a Stay booking

1. Run the site locally (section 2) or open the Vercel preview.
2. Open `/stay/`, choose dates, check availability and pick a room (001 to 005 in the sample data).
3. Sign in, then continue to payment.
4. Use a Paystack **test** card in the checkout window.
5. Confirm the receipt page shows the booking, then check the booking on the Dashboard (Bookings).

If the Paystack window shows "refused to connect" to `checkout.paystack.com`, the connection is being blocked on that device or network (ad blocker, firewall, VPN or a restrictive Wi-Fi). Try another browser or network. The site cannot fix this from its code.

If availability shows an error, the message names the exact problem. A "Could not find the function stay_room_availability" error means the site is connected to a Supabase project without the Stay migrations; check section 4.

---

## 11. Progress so far

- Website pages and shared header and footer, with a responsive layout.
- Accounts: sign up, sign in, password reset, and member space.
- Membership applications, Paystack payments, webhook handling and receipts.
- Admin dashboard: applications, members, homepage video, bookings, rooms and blocked dates.
- Stay online booking: live availability, 15-minute holds, Paystack checkout, verified confirmation and receipt, admin check-in and status changes.
- Database migrations for all of the above.
- Docker image and Vercel-ready static setup.

---

## 12. Known issues before launch

- Paystack public key is a placeholder, so online membership payment is disabled.
- `payment_transactions` rows are not created anywhere, so membership payments cannot be recorded (see 7.1).
- The older `/account/` page is still reachable, and its sign-up form does not match its script. It should be removed or redirected to `/login/`.
- Labs script throws an error on load (see the Labs section).
- Stay page links to `about.html`, `eat.html` and `labs.html` point to non-existent paths under `/stay/`.
- Eat checkout does not send orders to any backend.
- Contact form goes to a hardcoded personal address.
- Placeholder links remain in the footer and contact page.
- Stay online booking is ready to test with a Paystack test key. Confirm the full payment flow on a test booking before taking real payments.
- Stay refunds for mismatched or conflicting payments are manual. The booking is marked Refund required, and no admin screen for this exists yet.
- Check-in and check-out are recorded by staff by hand. Nothing marks a booking as no-show automatically.
- Several admin database functions (booking status, check-in, manual bookings, room blocks, membership approval) can be called by any signed-in user at the database level. Each must verify admin status inside the function; this needs a review before launch.
