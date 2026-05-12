# SES Bounce + Complaint Pipeline

Wires AWS SES bounce + complaint events back into Lewsnetter so the
`Subscriber#bounced_at` / `Subscriber#complained_at` columns get set and
mailkick auto-unsubscribes the address.

## Path of an event

```
  SES SendEmail (with configuration_set_name)
     -> SES delivers / fails
     -> SES publishes event to SNS topic (via Configuration Set event destination)
     -> SNS POSTs to https://lewsnetter.whinynil.co/webhooks/ses/sns
     -> Webhooks::Ses::SnsController routes by TopicArn -> Team::SesConfiguration
     -> Permanent bounce: subscriber.update!(subscribed: false, bounced_at: ...)
     -> Complaint:        subscriber.update!(subscribed: false, complained_at: ...)
```

The webhook itself is the public, unauthenticated entry point — it auto-confirms
SubscriptionConfirmation handshakes (GET to `SubscribeURL`), and rejects
notifications whose `TopicArn` doesn't match a known `Team::SesConfiguration`.

## AWS resources

All resources live in IK's AWS account `367541997824`, region `us-east-1`.

| Resource | Identifier |
| --- | --- |
| SES Configuration Set | `lewsnetter-default` |
| SNS bounce topic | `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces` (TO BE CREATED) |
| SNS complaint topic | `arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints` (TO BE CREATED) |

The configuration set was created during this rollout via the `lewsnetter` IAM
user. Inspect with:

```sh
set -a; source ~/.config/lewsnetter-ses-keys; set +a
aws sesv2 get-configuration-set --configuration-set-name lewsnetter-default --region us-east-1
```

## Rails side

- `Team::SesConfiguration#configuration_set_name` (string column, default
  `lewsnetter-default`) — per-team override of which SES configuration set
  every `SendEmail` call should reference.
- `SesSender.send_bulk` reads that column (falling back to
  `"lewsnetter-default"`) and passes it as `configuration_set_name:` to the SES
  v2 `SendEmail` API. Without that argument SES still sends but never publishes
  events, so the webhook never fires.
- `Ses::Verifier#call` backfills `configuration_set_name` on existing rows the
  first time a tenant re-runs verification — new rows get it via the DB default.
- `Webhooks::Ses::SnsController` was already in place before this change. It
  routes via the topic ARNs stored on `Team::SesConfiguration#sns_bounce_topic_arn`
  / `sns_complaint_topic_arn`.

## Outstanding work (blocked on IAM permissions)

The `lewsnetter` IAM user has SES permissions only — no `SNS:*` and no
`iam:ListUserPolicies`. The following four steps require either a privileged
operator or a policy update on the user to grant
`SNS:CreateTopic`, `SNS:Subscribe`, `SNS:GetTopicAttributes`,
`SNS:ListSubscriptionsByTopic` (scoped to the two ARNs above):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "sns:CreateTopic",
      "sns:Subscribe",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTopics"
    ],
    "Resource": [
      "arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-*"
    ]
  }]
}
```

### Step 1 — Create the two SNS topics

```sh
set -a; source ~/.config/lewsnetter-ses-keys; set +a
aws sns create-topic --name lewsnetter-ses-bounces   --region us-east-1
aws sns create-topic --name lewsnetter-ses-complaints --region us-east-1
```

Record the two ARNs.

### Step 2 — Subscribe each topic to the webhook

```sh
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces \
  --protocol https \
  --notification-endpoint https://lewsnetter.whinynil.co/webhooks/ses/sns \
  --region us-east-1

aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints \
  --protocol https \
  --notification-endpoint https://lewsnetter.whinynil.co/webhooks/ses/sns \
  --region us-east-1
```

Within ~30 seconds, each subscription should leave `PendingConfirmation` and
appear with a real ARN. Verify with:

```sh
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces \
  --region us-east-1
```

If they're stuck, check server logs:

```sh
ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  'docker logs $(docker ps --filter "name=lewsnetter-web" --format "{{.Names}}" | head -1) 2>&1 | grep SNS'
```

### Step 3 — Wire the configuration set to publish to those topics

```sh
aws sesv2 create-configuration-set-event-destination \
  --configuration-set-name lewsnetter-default \
  --event-destination-name lewsnetter-bounces \
  --event-destination 'Enabled=true,MatchingEventTypes=[BOUNCE,REJECT,RENDERING_FAILURE],SnsDestination={TopicArn=arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces}' \
  --region us-east-1

aws sesv2 create-configuration-set-event-destination \
  --configuration-set-name lewsnetter-default \
  --event-destination-name lewsnetter-complaints \
  --event-destination 'Enabled=true,MatchingEventTypes=[COMPLAINT],SnsDestination={TopicArn=arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints}' \
  --region us-east-1
```

Note: SES needs permission to `sns:Publish` to those topics. AWS adds the
necessary topic policy automatically when the destination is created with the
SES API, but if the SNS topic was created with a restrictive resource policy
beforehand, add the SES service principal manually.

### Step 4 — Populate topic ARNs on the live team

```sh
ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  'docker exec $(docker ps --filter "name=lewsnetter-web" --format "{{.Names}}" | head -1) \
   ./bin/rails runner "Team.first.ses_configuration.update!(
     sns_bounce_topic_arn:    %q{arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-bounces},
     sns_complaint_topic_arn: %q{arn:aws:sns:us-east-1:367541997824:lewsnetter-ses-complaints}
   )"'
```

### Step 5 — Round-trip test with the SES simulator

```sh
ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  'docker exec $(docker ps --filter "name=lewsnetter-web" --format "{{.Names}}" | head -1) \
   ./bin/rails runner "
team = Team.first
sub = team.subscribers.find_or_create_by!(email: %q{bounce@simulator.amazonses.com}) { |s|
  s.external_id = %q{bounce_test}; s.subscribed = true; s.name = %q{Bounce Test}
}
campaign = team.campaigns.first
SesSender.send_bulk(campaign: campaign, subscribers: [sub])
puts %Q{sent — waiting on bounce notification}
"'

sleep 90

ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  'docker exec $(docker ps --filter "name=lewsnetter-web" --format "{{.Names}}" | head -1) \
   ./bin/rails runner "
s = Team.first.subscribers.find_by(email: %q{bounce@simulator.amazonses.com})
pp s.reload.attributes.slice(%q{subscribed}, %q{bounced_at})
"'
```

Expected: `subscribed=false`, `bounced_at` present.

After verifying, delete the test subscriber:

```sh
ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 \
  'docker exec $(docker ps --filter "name=lewsnetter-web" --format "{{.Names}}" | head -1) \
   ./bin/rails runner "Team.first.subscribers.find_by(email: %q{bounce@simulator.amazonses.com})&.destroy"'
```

## Gotchas

- The configuration set was originally going to be created with
  `--tracking-options CustomRedirectDomain=lewsnetter.whinynil.co`. SES rejected
  this because the domain isn't a verified SES identity. The set was created
  without tracking options; once we build open/click tracking, the tracking
  domain must be added separately via `aws sesv2 put-configuration-set-tracking-options`.
- The webhook accepts notifications based on `TopicArn` match alone — we don't
  yet validate the SNS message signature. Anyone who knows a team's topic ARN
  could in theory forge a "bounce" and unsubscribe a known address. This is
  acceptable for MVP because the ARNs are not exposed and the worst case is an
  unwanted unsubscribe, but signature verification is a planned follow-up.
- `SesSender` always passes `configuration_set_name`, including for tenants
  who bring their own AWS credentials. If a tenant doesn't have a config set
  by that name in their account, SES will reject the send. When tenants
  onboard, either provision a config set in their account or let them override
  `Team::SesConfiguration#configuration_set_name` to a name that exists there
  (or to `nil`, which we treat as "use the default" — TODO: extend `SesSender`
  to honor an explicit `""` as "send without a configuration set").
