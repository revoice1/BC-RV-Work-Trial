<!-- DRAFT: match screenshots/wording to the production Okta sign-in experience and activation email template before sending. Password rules mirror the proposed policy in docs/okta-tenant-setup.md §3. -->

# 🔐 Setting Up Your Okta Account

> 📅 **Your activation day: [DATE].** You'll get an email from Okta inviting you to activate your new AiLense account. Okta becomes the way you sign in to your work apps.

> ⚠️ **Have your phone or YubiKey with you before you start.** You'll set up a security check (MFA) as part of activation and can't finish without it.

## What's happening?

AiLense is moving to **Okta** for signing in to work apps. It's more reliable than our old system and keeps your account more secure. After setup, you'll sign in at **`ailense.okta.com`**.

## ✅ Before You Start

- [ ] **Set aside about 15 minutes**
- [ ] **Have your phone or YubiKey** (ideally both, so you have a backup)
- [ ] **Use your work laptop** (Okta Verify is already installed on it by IT)
- [ ] **Have 1Password open** to save your new password

## 🚀 Step by Step

### 1. Open the invitation email

Look for an email from **Okta** with the subject **"Activate your AiLense account"** **[confirm subject]**.

> 🛡️ **Check the link before you click:** it should go to **`https://ailense.okta.com`**. If it goes anywhere else, don't click it. Report it in **#it-support**.

Click **Activate**. The link expires after **[N] days**. If it has expired, ask in #it-support for a new one.

### 2. Create your password

- At least **14 characters**. A passphrase is easiest: e.g., four random words
- Can't be a common or previously leaked password
- **Don't reuse** a password from any other account
- **Save it in 1Password**

You won't be asked to change it on a schedule. Only change it if you think it's been exposed.

### 3. Set up your security check (MFA)

Choose at least one. **Setting up both gives you a backup** if you lose one.

#### Option A: Okta Verify on your phone

1. Install **Okta Verify** from the App Store or Google Play (publisher: **Okta, Inc.**)
2. In the app, tap **Add account** and scan the QR code shown on your computer screen
3. **Allow notifications** when asked

When you sign in later, Okta shows a **number** on your screen. Tap the **matching number** on your phone.

#### Option B: YubiKey

1. Choose **Security Key or Biometric**
2. Insert your YubiKey when prompted and **touch it**

### 4. Set up Okta Verify on your laptop

Okta Verify is already installed on your work laptop.

1. Open **Okta Verify** on your laptop
2. Click **Add account** and sign in with your AiLense email, new password, and your phone or YubiKey
3. Done

After this, signing in on your laptop is usually just a click or a fingerprint. No codes, no phone.

### 5. Check it worked

Go to **`ailense.okta.com`**. You should see your **Okta dashboard** with your work apps.

## 🛡️ Stay Safe

- **Never approve a sign-in you didn't start.** If your phone asks you to approve something out of the blue, **deny it** and report it in **#it-support** right away.
- **IT will never ask for your password or a code**, over Slack, email, or phone.
- Okta sign-in only happens at **`ailense.okta.com`**.

## 🆘 Need Help?

> 🚨 **Stuck, see an error, or something looks wrong? Message [#it-support](#) on Slack.**
> A screenshot or photo of the screen helps.

## ❓ FAQ

<details>
<summary><strong>Do I still use my old password?</strong></summary>

For a few weeks, yes, for some apps. We're moving apps to Okta in stages and will tell you as each one moves. Once everything is on Okta, your old password goes away.
</details>

<details>
<summary><strong>My invitation link expired.</strong></summary>

Ask in **#it-support** and we'll send a new one.
</details>

<details>
<summary><strong>I'm getting a new phone.</strong></summary>

Before you switch, message **#it-support** so we can move Okta Verify to your new phone. If you set up a YubiKey too, you can use it in the meantime.
</details>

<details>
<summary><strong>I lost my phone or YubiKey.</strong></summary>

Message **#it-support** right away. We'll verify it's you (usually a quick video call) and reset your security check.
</details>

<details>
<summary><strong>Why does it show me a number to match?</strong></summary>

It proves you're the one signing in. Attackers sometimes send repeated sign-in requests hoping you'll tap "approve" to make them stop. Matching the number stops that.
</details>
