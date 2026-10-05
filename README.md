# MailReveal

MailReveal intercepts `message:` links and reveals the referenced email in Apple Mail’s existing three-pane viewer instead of leaving it in a separate message window.

The app is a menu-less native macOS utility. It looks up the RFC Message-ID in Mail’s local Envelope Index to find the message’s account and mailbox, uses AppleScript to switch the existing viewer to that mailbox and select the message, and uses Accessibility to expand the conversation so the exact message is selected. Each selection is checked against the Message-ID that Mail reports.

## Requirements

- macOS 13 or later
- Apple Mail
- Swift 6 or later from Xcode or the Command Line Tools

## Build

Run the tests and build the app bundle:

```shell
./Scripts/swiftpm.sh test
./Scripts/build-app.sh
```

The built app is written to `dist/MailReveal.app` and receives an ad-hoc signature suitable for local use.

## Test without changing the default handler

Open a known Mail Message-ID explicitly with the built app:

```shell
open -a "$PWD/dist/MailReveal.app" 'message://%3Cmessage-id%40example.com%3E'
```

Mail must be running. MailReveal needs three permissions:

- **Full Disk Access**, to read Mail’s Envelope Index in `~/Library/Mail`. Enable the app under **System Settings → Privacy & Security → Full Disk Access**.
- **Accessibility**, to find and expand the conversation in Mail’s message list. Enable the app under **System Settings → Privacy & Security → Accessibility**.
- **Automation** of Mail, to change the viewer’s mailbox and selection. macOS asks for this the first time MailReveal runs.

MailReveal does not open System Settings automatically. Grant Full Disk Access and Accessibility before testing.

## Installation

Copy the built app to `~/Applications/MailReveal.app` and register it as the default handler for the `message:` scheme. macOS has no settings UI for this; one option is the third-party [duti](https://github.com/moretension/duti) tool:

```shell
duti -s app.mailreveal.utility message
```

A normal link can then be tested without naming the app explicitly:

```shell
open 'message://%3Cmessage-id%40example.com%3E'
```

Rebuilding `dist/MailReveal.app` does not update the installed copy automatically.

## Current scope

- Success is silent: Mail comes forward with the message selected.
- Failures produce an alert. Unless the link itself is malformed, MailReveal then hands it to Mail, which opens the message in its own window.
- Incoming links are validated and normalised before they are looked up.
- MailReveal reads Mail’s Envelope Index read-only and does not persist message data. It reads the target message’s index row and visible message-list labels in memory to select and verify the exact message.
