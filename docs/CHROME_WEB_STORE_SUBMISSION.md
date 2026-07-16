# Chrome Web Store Submission Notes

These notes apply separately to the Twitch and YouTube extension packages. They are preparation material only; no store dashboard submission is automated by this repository.

## Shared answers

- **Single purpose:** Export user-authorized media from the active Twitch or YouTube page to local files through a Windows native host.
- **Remote code:** No remote JavaScript or executable code is loaded by the extension. Local helper binaries are invoked by the native host after installation.
- **Data use:** The extension stores user preferences in `chrome.storage.sync` and sends the user-selected page URL/options to the local native host when an export is explicitly started.
- **Developer service:** Generated media is not uploaded to a developer-operated service, and the project does not run analytics or advertising.
- **Privacy policy:** `https://www.dowen.idv.tw/local_exporters/privacy.html`
- **Homepage:** `https://www.dowen.idv.tw/local_exporters/`
- **Support:** `https://www.dowen.idv.tw/local_exporters/support.html`

## Twitch permission justifications

- `activeTab`: Read the active Twitch VOD page only when the user opens the popup and starts an export.
- `cookies`: Read user-authorized Twitch cookies needed by the local downloader for the requested export.
- `storage`: Store export preferences such as output folder text, formats, chat options, and subtitle options.
- `nativeMessaging`: Send the explicit export request to the local Windows native host.
- Twitch host permissions: Restrict page integration to Twitch pages where the extension's VOD controls operate.

## YouTube permission justifications

- `activeTab`: Read the active YouTube page only when the user opens the popup and starts an export.
- `cookies`: Read user-authorized YouTube cookies needed by the local downloader for the requested export.
- `storage`: Store export preferences such as output folder text, formats, and subtitle options.
- `nativeMessaging`: Send the explicit export request to the local Windows native host.
- YouTube host permissions: Restrict page integration to YouTube pages where the extension's export controls operate.

Before submission, verify the final GitHub Pages URL and paste the current package version and release artifact into the store dashboard.

The manifests include public signing keys so local unpacked installations have stable IDs. Chrome Web Store publication may assign or manage a store signing identity separately; verify the final store ID before publishing native host allowlists for the store listing.
