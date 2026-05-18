# Setting up Amazon SES

Lewsnetter sends every campaign through **your own AWS Simple Email Service account**. There is no shared sending pool, no per-message markup, and no middle-man hop. You bring the AWS keys, you own the sender reputation, and you pay AWS directly (~$0.10 per thousand emails at the time of writing).

## Why BYO-SES

- **Deliverability is yours to keep or lose.** A shared sending IP means one customer's spam complaint hurts everyone on it. With your own SES identity, your warmup, your bounces, and your engagement signals stay on a domain you control.
- **You own the contract with AWS.** No vendor lock-in on the most expensive line item (sending). If you stop using Lewsnetter, your sending infrastructure keeps working.
- **Cost.** SES is the cheapest reputable transactional/marketing email vendor on the market — $0.10 per 1,000 emails outside the EC2 free tier.
- **Compliance.** Bounce and complaint webhooks land directly in your AWS account before they ever touch Lewsnetter. SNS topic, your subscription, your retention.

The tradeoff: you have to do the AWS setup. This document walks you through it once.

## AWS prerequisites

- An AWS account. Use the root account once to create an IAM user, then never log in as root again.
- A region. **`us-east-1` (N. Virginia)** is the default — it has the largest daily quota out of the gate and the cheapest egress for North American sends. If most of your subscribers are in Europe, pick `eu-west-1` (Ireland) or `eu-central-1` (Frankfurt). The region you pick is where SES will sign your messages; you cannot move identities between regions without re-verifying.
- A domain you can edit DNS for (you'll add CNAMEs).

## Step 1 — Create an IAM user for Lewsnetter

Open the [IAM Users console](https://console.aws.amazon.com/iam/home#/users) and create a new user — name it something obvious like `lewsnetter-ses`. **Do not give it console access.** This user only needs programmatic credentials.

Attach the following inline policy. This is the minimum surface Lewsnetter actually calls (verified against `app/services/ses/` — we do not use any SES action not listed here):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ses:SendEmail",
      "ses:SendRawEmail",
      "ses:GetAccount",
      "ses:GetSendQuota",
      "ses:ListEmailIdentities",
      "ses:CreateEmailIdentity",
      "ses:GetEmailIdentity",
      "ses:DeleteEmailIdentity",
      "ses:PutEmailIdentityConfigurationSetAttributes"
    ],
    "Resource": "*"
  }]
}
```

If you want to also let Lewsnetter receive bounce/complaint notifications via SNS, add:

```json
"sns:CreateTopic",
"sns:Subscribe",
"sns:ListSubscriptionsByTopic",
"sns:GetTopicAttributes"
```

Lewsnetter's SES code is in `app/services/ses/`. The actions above cover everything in `client_for.rb`, `identity_checker.rb`, `identity_creator.rb`, `domain_identity_checker.rb`, `domain_identity_creator.rb`, `verifier.rb`, and `test_sender.rb`. If you grant a broader policy (like the AWS-managed `AmazonSESFullAccess`), it works but is overprovisioned.

## Step 2 — Generate an Access Key

With the user selected:

1. Open the **Security credentials** tab.
2. Under **Access keys**, click **Create access key**.
3. Pick **Other** as the use case.
4. AWS will display the Access Key ID and Secret Access Key **once**. Copy both immediately — you cannot recover the secret later.

You will paste these into Lewsnetter in the next step. Treat them like a database password: stored encrypted at rest (`encrypts :encrypted_access_key_id, :encrypted_secret_access_key` on `Team::SesConfiguration`), never logged, never displayed back to you.

## Step 3 — Connect SES inside Lewsnetter

In the app, navigate to **Email Sending → Setup** (route: `account_team_setup_email_sending_path`, i.e. `/account/teams/:team_slug/email_sending/setup`). The four-step wizard:

1. **Credentials.** Paste the Access Key ID + Secret + region. Click **Verify with AWS**. Lewsnetter calls `Ses::Verifier` under the hood — it runs `GetAccount` to confirm the keys work, reads your current send quota, and lists any verified identities already on the account. If anything is wrong (bad key, wrong region, quota exhausted), you'll see the AWS error message inline.
2. **Domain.** Enter the domain you want to send from (e.g. `mail.yourbrand.com` or just `yourbrand.com`). Lewsnetter calls `Ses::DomainIdentityCreator`, which asks SES to provision an Easy DKIM identity (2048-bit RSA). SES returns three DKIM token names; Lewsnetter shows you the three CNAME records you need to add to your DNS.
3. **Verify DNS.** Add the three CNAMEs to your DNS provider. They look like:

   ```
   <token1>._domainkey.yourbrand.com  CNAME  <token1>.dkim.amazonses.com
   <token2>._domainkey.yourbrand.com  CNAME  <token2>.dkim.amazonses.com
   <token3>._domainkey.yourbrand.com  CNAME  <token3>.dkim.amazonses.com
   ```

   The wizard polls `Ses::DomainIdentityChecker` every few seconds. When all three CNAMEs propagate and SES verifies them, the domain flips to `verified` and Lewsnetter auto-provisions `noreply@yourbrand.com` as your first sender address.
4. **Test send.** Lewsnetter sends a real, signed test email through your SES to the inbox of your choice via `Ses::TestSender`. If you receive it, you're done.

DNS propagation usually completes in minutes if you're on Cloudflare/Route53, but can take up to 48 hours on slower registrars. The wizard keeps polling — you can close the tab and come back.

## Step 4 — Get out of the SES sandbox

**This is the step everyone forgets.** By default, every new AWS account is in the SES **sandbox**:

- You can only send to verified email addresses (every recipient must verify themselves first).
- You're capped at 200 emails per 24h, 1 per second.

To send to your actual subscriber list you need to request production access:

1. In the AWS Console, go to **Amazon SES → Account dashboard** in the region you set up.
2. Click **Request production access** (top-right banner).
3. Fill out the form. AWS wants:
   - **Mail type:** Marketing (for newsletters) or Transactional (for system mail).
   - **Website URL:** Your domain.
   - **Use case description:** One paragraph explaining what you'll send. Be specific — "marketing emails to subscribers who opt in via a double opt-in form on our website. Bounces and complaints handled via SNS. Hard bounces auto-unsubscribed." AWS rejects vague descriptions.
   - **Compliance:** Confirm you only send to people who explicitly subscribed. Lewsnetter's signup flow and the per-campaign unsubscribe link in every footer cover this.
4. Submit. Approval usually takes **24 hours**, sometimes 1-3 days. Approval is per-region — if you later add a second region, you'll need to request again there.

Once approved your daily quota jumps from 200 to 50,000 (and grows automatically as you send healthy mail). The Lewsnetter sending settings page will show the new quota.

## What domain verification actually does

When you verify a domain with Easy DKIM (the flow above), SES generates a 2048-bit RSA keypair, holds the private key, and gives you three public selector tokens. You publish those tokens as CNAMEs in your DNS. From that point:

- Every email Lewsnetter sends through SES is **signed** with that private key.
- Receiving mail servers (Gmail, Outlook, etc.) fetch the public key via the CNAME chain and verify the signature.
- A valid DKIM signature on a domain you own is the single largest deliverability signal. Without it, you're going to spam.

The verification also covers every address on that domain. You can add `hello@yourbrand.com`, `news@yourbrand.com`, etc. as sender addresses in Lewsnetter without re-verifying — `Ses::IdentityChecker` recognizes domain-verified senders and marks them `domain_verified` automatically.

## FAQ

**Can I use SES credentials I already have for another app?**
Yes. Lewsnetter stores credentials per-team, so you can paste keys from an existing IAM user as long as they have the policy actions listed above. The wizard's verification step is non-destructive — it just reads your account state.

**What happens to bounces and complaints?**
Lewsnetter currently relies on AWS's default suppression list (SES auto-suppresses hard bounces and complaints account-wide). Per-team SNS webhook routing is on the roadmap but not yet shipped — you can configure SNS topics manually in your AWS account if you want bounce events delivered elsewhere.

**Can I send from multiple domains?**
Not from a single team — Lewsnetter's UI assumes one verified domain per team. You can work around this by creating multiple teams, each with its own SES configuration. Multi-domain-per-team is a known gap.

**The wizard says my domain is "pending" but I added the CNAMEs hours ago.**
Run `dig <token1>._domainkey.yourbrand.com CNAME` and confirm it returns the SES target. If it doesn't, check your DNS provider for typos (the underscore before `_domainkey` is mandatory). If it does, click **Re-check with SES** in the wizard — `Ses::DomainIdentityChecker` will pull fresh status from AWS.

**My SES account is suspended. Now what?**
AWS suspends accounts with high bounce rates (>5%) or complaint rates (>0.1%). The fix is the same in any system: pause sending, clean your list (remove unengaged addresses), respond to the AWS reviewer's email explaining what happened and what you'll do differently, and request reinstatement. Lewsnetter cannot help with reinstatement — this is between you and AWS.

**Can I use a non-AWS SMTP relay (SendGrid, Postmark, Mailgun)?**
Not currently. The sending path is hardcoded to `aws-sdk-sesv2`. Adding an alternative provider is a few hundred lines in `app/services/ses_sender.rb` and friends — happy to merge a PR.
