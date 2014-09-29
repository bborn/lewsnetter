# LewsNetter

E-mail marketing application. Send e-mails via SES. Subscription management, delivery, bounce, and complaint notifications. Templates.

## Deploy

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

You'll need to enter your SES credentials and your SES SMTP credentials in order to send mail ([http://docs.aws.amazon.com/ses/latest/DeveloperGuide/smtp-credentials.html](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/smtp-credentials.html)). For more info on setting up SES in general, see [here](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/setting-up-ses.html).


## Getting Started

Go to `/a/signup` and create an account.

Using the console, turn that account into an admin user (`user.is_admin = true`)

### Creating a mailing list

To create a mailing list go to `/mailing_lists/new`. To import users into the list, upload a CSV file with headings for `email`, `name`, and `created_at` ('created_at' is the date when the user subscribed).

CSV import (and lots of other things) happen asynchronously in [Sidekiq](http://sidekiq.org/). Make sure you have workers running, or use [Hirefire.io](http://hirefire.io) (or some other method) to auto scale your workers.


### Templates

While your mailing list is importing, create an e-mail template `/templates/new`. A template should be a complete HTML document with editable regions. The template will be used as the layout for your e-mail campaigns, and will be run through Premailer (so CSS will be inlined).

To make a section of the template editable, give the DOM node the 'editable' class and give it a unique id. For example:

```html
<div class='editable' id='main_content'>
  This text will be editable
</div>
```

There are some interpolations you can use within your template:

* `%{currentdayname}`
* `%{currentday}`
* `%{currentmonthname}`
* `%{currentyear}`
* `%{unsubscribe}` - inserts an unsubscribe link
* `%{webversion}`  - inserts a link to the web version

### Add a sender address

Before you create a campaign, you need to add a sender address (the address from which the e-mails will be sent). To do this, go to the admin section (`/admin/sender_address`) and add a new address. The app will attempt to verify the address through SES after you create it (you should get a confirmation e-mail from Amazon at that address asking you to click a link to verify it).

### Campaigns

#### Create & Edit
You can create a campaign at `/campaigns/new`. Add a subject line, select a sender address, a mailing list, and a template.

Once your campaign has been created, you can edit it to add content. The content editing interface uses an [inline rich text editor](https://github.com/daviferreira/medium-editor/). Occassionally it doesn't load correctly (something to do with Turbolinks). If that happens just refresh the page and it should work (working on fixing this).

The rich text editor will make any regions in your template marked with the class 'editable', um, editable. You can click in them to edit their contents. To add an image, insert the url to the image, highlight it, and then click 'image' in the popup toolbar.

Alternatively, you can use the 'fetch feed items' button in the sidebar to grab a bunch of items from a feed you specify, and then load them into the editor (this is a work in progress, so experiment).

#### Preview
You can send a preview of your campaign to yourself (or others) using the panel on the `Campaigns#show` page.

#### Queue

Once you're happy with your campaign content, you can queue it (the 'queue' button on same page). Queueing is done in Sidekiq, and can take a while depending on the size of your mailing list and the number of workers you have running. By default LewsNetter will spawn one worker per 100 subscribers, but that setting is customizable (just add a Setting in `/admin/settings` called `queue.batch_size`).

#### Send

Once your campaign has queued, you'll see a 'Send' button on the show campaign page. That is the button you will click in order to send the campaign, thus, its name. Sending, like queueing, happens in a background Sidekiq job, and uses the same `queue.batch_size` setting to allocate workers.

You can monitor Sidekiq at `/admin/sidekiq/jobs`.

#### Stats

Once the campaign begins sending you'll start to see stats (again, on the campaign show page, i.e. `/campaigns/CAMPAIGN_ID`). If you have SNS notifications set up (see below) you'll see deliveries, complaints, bounces, and opens. If not, you'll just see opens (LewsNetter inserts a tracking pixel image into every e-mail).


### Setting up notifications

You'll want to set up SES to post notifications to SNS Topics, which will in turn post messages to your app.

Read the docs [here](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/configure-sns-notifications.html)

Basically, you set up SNS Topics to receive notifications from SES and then post messages to your app. Your SNS Topics should post to the appropriate endpoint for each type of notification:

* Bounces     -->   http://yourinstall.com/bounces
* Deliveries  -->   http://yourinstall.com//deliveries
* complaints  -->   http://yourinstall.com//complaints

TODO - better docs on this

### E-mail & domain verification and DKIM settings

[http://docs.aws.amazon.com/ses/latest/DeveloperGuide/authentication.html](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/authentication.html)

[http://docs.aws.amazon.com/ses/latest/DeveloperGuide/improve-deliverability.html](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/improve-deliverability.html)







