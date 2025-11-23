# PaperGist

iOS app that generates summaries of academic papers from your Zotero library using on-device Apple Intelligence.

## What it does

PaperGist connects to your Zotero library, finds papers with PDF attachments, and creates structured summaries using Apple's Foundation Models Framework. All processing happens on your device—no external AI services, no data sent anywhere.

Summaries get saved back to Zotero as child notes attached to the original paper. You can process individual papers or run batch jobs. The app tracks progress with live activities and handles incremental library syncing to avoid re-downloading your entire library every time.

## Privacy approach

The Foundation Models Framework runs entirely on-device. Your papers never leave your phone or iPad. No analytics, no telemetry, no external API calls for summarisation. The only network requests go to Zotero's API to fetch your library and upload summaries back.

## Requirements

Hardware
- iPhone 16 Pro or later (A17 Pro chip minimum)
- iPad with M4 chip or later

Software
- iOS/iPadOS 26.0+
- Apple Intelligence enabled on your device
- Xcode 16.0+ (for development)
- Swift 6.0

Zotero
- Active Zotero account
- Library must use Zotero's web sync (not WebDAV or other sync methods)

## Project setup

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project file from `project.yml`. Install it first:

```bash
brew install xcodegen
```

Then generate the project:

```bash
xcodegen generate
```

### OAuth credentials

You need to register your own Zotero OAuth application to use the API:

1. Go to https://www.zotero.org/oauth/apps
2. Create a new application
3. Set the callback URL to `papergist://oauth-callback`
4. Copy your consumer key and secret

Create `PaperGist/Utilities/ZoteroConfig.swift`:

```swift
import Foundation

enum ZoteroConfig {
    static let consumerKey = "YOUR_CONSUMER_KEY"
    static let consumerSecret = "YOUR_CONSUMER_SECRET"
    static let callbackURL = "papergist://oauth-callback"
}
```

This file is gitignored to keep credentials out of version control.

### Building

Open `PaperGist.xcodeproj` in Xcode 16+ and build. The project targets iOS 26.0 minimum. You'll need to test on a physical device with Apple Intelligence—the simulator won't work for Foundation Models.

## Architecture

**SwiftUI** for the interface. **SwiftData** for local persistence (library items, summaries, job tracking). **MVVM** pattern keeps view logic separate from business logic.

**Services:**
- `ZoteroOAuthService` - OAuth 1.0a authentication flow
- `ZoteroService` - All Zotero API operations (fetch library, download PDFs, upload notes)
- `AIService` - Wrapper around Foundation Models Framework
- `SummarisationService` - Orchestrates the full pipeline (download → extract → summarise → upload)
- `PDFTextExtractor` - Pulls text from PDFs, handles scanned documents with fallback strategies
- `BackgroundTaskManager` - Schedules background processing
- `LiveActivityManager` - Updates live activities during batch jobs
- `NotificationManager` - Sends local notifications when jobs complete

The summarisation pipeline runs mostly off the main thread. Heavy I/O (PDF downloads, text extraction, Zotero uploads) happens in a background actor. Only AI generation requires the main actor since Foundation Models sessions need it.

## Features

Library sync
- Incremental syncing based on Zotero's library version headers
- Fetches only items modified since last sync
- Supports user and group libraries
- Handles pagination for large libraries

Summarisation
- Customisable prompts (default adapts to paper type: empirical, theoretical, review, etc.)
- Three summary lengths: short (100-150 words), medium (200-300 words), long (400-500 words)
- Confidence scores from the model
- Automatic tagging (#ai-summary) optional
- Text extraction fallbacks for scanned PDFs

Batch processing
- Process 1-50 papers at once
- Live activity shows progress
- Cancel jobs mid-flight
- Background task support for processing when app is backgrounded

App Intents
- Shortcuts integration for automation
- Query library stats
- Start batch jobs from Shortcuts
- Fetch summaries programmatically

## Zotero sync requirements

This app only works with Zotero's built-in web sync. If you currently use WebDAV or file-based syncing, you'll need to:

1. Enable web sync in Zotero preferences
2. Let your library sync to Zotero's servers
3. Then PaperGist can access it

The app uses OAuth for authentication, so you never enter your Zotero password. You can revoke access any time from your Zotero account settings.

## Configuration

Settings live in `AppSettings` (stored in UserDefaults):

- `skipItemsWithNotes` - Skip papers that already have any notes attached
- `autoUploadToZotero` - Upload summaries immediately vs. save locally only
- `addAISummaryTag` - Tag processed items with #ai-summary
- `customPrompt` - Override the default summarisation prompt
- `summaryLength` - short/medium/long
- `batchSize` - How many papers to process in a batch job (1-50)
- `backgroundSyncEnabled` - Allow background processing

## Testing notes

Foundation Models only runs on physical devices with Apple Intelligence enabled. The simulator will throw `modelNotAvailable` errors. You need a real iPhone 16 Pro or newer, or an iPad with M4.

PDF text extraction can be slow on scanned documents. The app has fallback strategies (extract abstract only, or introduction + conclusion) when full extraction fails or times out.

## Licence

MPL-2.0
